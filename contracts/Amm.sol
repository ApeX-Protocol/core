pragma solidity ^0.8.0;

import "./interfaces/IAmm.sol";
import "./interfaces/IVault.sol";
import "./LiquidityERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";
import "./libraries/AMMLibrary.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IPriceOracle.sol";
import "./libraries/FullMath.sol";
import {IConfig} from "./interfaces/IConfig.sol";

contract Amm is IAmm, LiquidityERC20 {
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    uint256 public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public baseToken;
    address public quoteToken;
    address public config;
    address public margin;
    address public vault;

    uint112 private baseReserve; // uses single storage slot, accessible via getReserves
    uint112 private quoteReserve; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    //todo
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    // uint256 public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint256 private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "AMM: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves()
        public
        view
        returns (
            uint112 _baseReserve,
            uint112 _quoteReserve,
            uint32 _blockTimestampLast
        )
    {
        _baseReserve = baseReserve;
        _quoteReserve = quoteReserve;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "AMM: TRANSFER_FAILED");
    }

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(
        address _baseToken,
        address _quoteToken,
        address _config,
        address _margin,
        address _vault
    ) external {
        require(msg.sender == factory, "Amm: FORBIDDEN"); // sufficient check
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        config = _config;
        margin = _margin;
        vault = _vault;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "AMM: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        baseReserve = uint112(balance0);
        quoteReserve = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(baseReserve, quoteReserve);
    }

    // this low-level function should be called from a contract which performs important safety checks
    //todo
    function mint(address to) external lock returns (uint256 quoteAmount, uint256 liquidity) {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        uint256 baseAmount = IERC20(baseToken).balanceOf(address(this));

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        uint256 quoteAmountMinted;
        if (_totalSupply == 0) {
            quoteAmountMinted = getQuoteAmountByPriceOracle(baseAmount);
            liquidity = Math.sqrt(baseAmount.mul(quoteAmountMinted)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            quoteAmountMinted = getQuoteAmountByCurrentPrice(baseAmount);
            liquidity = Math.minU(
                baseAmount.mul(_totalSupply) / _baseReserve,
                quoteAmountMinted.mul(_totalSupply) / _quoteReserve
            );
        }
        require(liquidity > 0, "AMM: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(_baseReserve + baseAmount, _quoteReserve + quoteAmountMinted, _baseReserve, _quoteReserve);
        _safeTransfer(baseToken, vault, baseAmount);
        quoteAmount = quoteAmountMinted;
        emit Mint(msg.sender, to, baseAmount, quoteAmountMinted, liquidity);
    }

    function getQuoteAmountByCurrentPrice(uint256 baseAmount) internal returns (uint256 quoteAmount) {
        return AMMLibrary.quote(baseAmount, uint256(baseReserve), uint256(quoteReserve));
    }

    function getQuoteAmountByPriceOracle(uint256 baseAmount) internal returns (uint256 quoteAmount) {
        // get price oracle
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        address priceOracle = IConfig(config).priceOracle();
        quoteAmount = IPriceOracle(priceOracle).quote(baseToken, quoteToken, baseAmount);
    }


    //todo 
    function getSpotPrice() public returns (uint256) {
        if (quoteReserve == 0) {
            return 0;
        }
        return uint256(UQ112x112.encode(baseReserve).uqdiv(quoteReserve));
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        address _baseToken = baseToken; // gas savings

        uint256 vaultAmount = IERC20(_baseToken).balanceOf(address(vault));
        uint256 liquidity = balanceOf[address(this)];

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(_baseReserve) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(_quoteReserve) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, "AMM: INSUFFICIENT_LIQUIDITY_BURNED");
        require(amount0 <= vaultAmount, "AMM: not enough base token withdraw");

        _burn(address(this), liquidity);

        uint256 balance0 = _baseReserve - amount0;
        uint256 balance1 = _quoteReserve - amount1;

        _update(balance0, balance1, _baseReserve, _quoteReserve);
        //  if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        // vault withdraw
        IVault(vault).withdraw(to, amount0);
        emit Burn(msg.sender, to, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(
        address inputAddress,
        address outputAddress,
        uint256 inputAmount,
        uint256 outputAmount
    ) external onlyMargin lock returns (uint256[2] memory amounts) {
        require(inputAmount > 0 || outputAmount > 0, "AMM: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();

        require(inputAmount < _baseReserve && outputAmount < _quoteReserve, "AMM: INSUFFICIENT_LIQUIDITY");

        uint256 _inputAmount;
        uint256 _outputAmount;

        if (inputAddress != address(0x0) && inputAmount != 0) {
            _outputAmount = swapInput(inputAddress, inputAmount);
            _inputAmount = inputAmount;
        } else {
            _inputAmount = swapOutput(outputAddress, outputAmount);
            _outputAmount = outputAmount;
        }
        emit Swap(inputAddress, outputAddress, _inputAmount, _outputAmount);
        return [_inputAmount, _outputAmount];
    }

    function swapQuery(
        address inputAddress,
        address outputAddress,
        uint256 inputAmount,
        uint256 outputAmount
    ) public view returns (uint256[2] memory amounts) {
        require(inputAmount > 0 || outputAmount > 0, "AMM: INSUFFICIENT_OUTPUT_AMOUNT");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        require(inputAmount < _baseReserve && outputAmount < _quoteReserve, "AMM: INSUFFICIENT_LIQUIDITY");

        uint256 _inputAmount;
        uint256 _outputAmount;

        if (inputAddress != address(0x0) && inputAmount != 0) {
            _outputAmount = swapInputQuery(inputAddress, inputAmount);
            _inputAmount = inputAmount;
        } else {
            _inputAmount = swapOutputQuery(outputAddress, outputAmount);
            _outputAmount = outputAmount;
        }

        return [_inputAmount, _outputAmount];
    }

    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external onlyMargin {
        require((inputToken == baseToken || inputToken == quoteToken), " wrong input address");
        require((outputToken == baseToken || outputToken == quoteToken), " wrong output address");
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        uint256 balance0;
        uint256 balance1;
        if (inputToken == baseToken) {
            balance0 = baseReserve + inputAmount;
            balance1 = quoteReserve - outputAmount;
        } else {
            balance0 = baseReserve - outputAmount;
            balance1 = quoteReserve + inputAmount;
        }
        _update(balance0, balance1, _baseReserve, _quoteReserve);
        emit ForceSwap(inputToken, outputToken, inputAmount, outputAmount);
    }

    function rebase() public {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        uint256 quoteReserveDesired = getQuoteAmountByPriceOracle(_baseReserve);
        //todo config
        if (
            quoteReserveDesired.mul(100) >= uint256(_quoteReserve).mul(105) ||
            quoteReserveDesired.mul(100) <= uint256(_quoteReserve).mul(95)
        ) {
            _update(_baseReserve, quoteReserveDesired, _baseReserve, _quoteReserve);

            emit Rebase(_quoteReserve, quoteReserveDesired, _baseReserve);
        }
    }

    function swapInput(address inputAddress, uint256 inputAmount) internal returns (uint256 amountOut) {
        require((inputAddress == baseToken || inputAddress == quoteToken), "AMM: wrong input address");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        uint256 balance0;
        uint256 balance1;

        if (inputAddress == baseToken) {
            amountOut = AMMLibrary.getAmountOut(inputAmount, _baseReserve, _quoteReserve);
            balance0 = _baseReserve + inputAmount;
            balance1 = _quoteReserve - amountOut;
            // if necessary open todo
            // uint balance0Adjusted = balance0.mul(1000).sub(inputAmount.mul(3));
            // uint balance1Adjusted = balance1.mul(1000);
            // require(balance0Adjusted.mul(balance1Adjusted) >= uint(_baseReserve).mul(_quoteReserve).mul(1000**2), 'AMM: K');
        } else {
            amountOut = AMMLibrary.getAmountOut(inputAmount, _quoteReserve, _baseReserve);
            balance0 = _baseReserve - amountOut;
            balance1 = _quoteReserve + inputAmount;
        }
        _update(balance0, balance1, _baseReserve, _quoteReserve);
    }

    function swapOutput(address outputAddress, uint256 outputAmount) internal returns (uint256 amountIn) {
        require((outputAddress == baseToken || outputAddress == quoteToken), "AMM: wrong output address");
        uint256 balance0;
        uint256 balance1;
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        if (outputAddress == baseToken) {
            amountIn = AMMLibrary.getAmountIn(outputAmount, _quoteReserve, _baseReserve);
            balance0 = _baseReserve - outputAmount;
            balance1 = _quoteReserve + amountIn;
        } else {
            amountIn = AMMLibrary.getAmountIn(outputAmount, _baseReserve, _quoteReserve);
            balance0 = _baseReserve + amountIn;
            balance1 = _quoteReserve - outputAmount;
        }
        _update(balance0, balance1, _baseReserve, _quoteReserve);
    }

    function swapInputQuery(address inputAddress, uint256 inputAmount) internal returns (uint256 amountOut) {
        require((inputAddress == baseToken || inputAddress == quoteToken), "AMM: wrong input address");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings

        if (inputAddress == baseToken) {
            amountOut = AMMLibrary.getAmountOut(inputAmount, _baseReserve, _quoteReserve);
        } else {
            amountOut = AMMLibrary.getAmountOut(inputAmount, _quoteReserve, _baseReserve);
        }
    }

    function swapOutputQuery(address outputAddress, uint256 outputAmount) internal returns (uint256 amountIn) {
        require((outputAddress == baseToken || outputAddress == quoteToken), "AMM: wrong output address");

        uint256 amountIn;
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings

        if (outputAddress == baseToken) {
            amountIn = AMMLibrary.getAmountIn(outputAmount, _quoteReserve, _baseReserve);
        } else {
            amountIn = AMMLibrary.getAmountIn(outputAmount, _baseReserve, _quoteReserve);
        }
    }

    function swapQueryWithAcctSpecMarkPrice(
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            uint256 outputAmount
        ) external view returns (uint256[2] memory amounts) {

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        
         uint256  inputSquare =     inputAmount * inputAmount;
       // L/vusd > 10000
        uint256 _inputAmount = inputAmount;
        uint256 _outputAmount; 


        if(FullMath.mulDiv(_baseReserve,_quoteReserve,inputSquare )>=10000){
            _outputAmount = AMMLibrary.quote(inputAmount, _quoteReserve, _baseReserve);
        } else {
         // (sqrt(y/x)+ betal * deltay/L)   
         uint L =  uint(_baseReserve) * uint(_quoteReserve);
         uint beta = Iconfig(config).beta();
         require(beta>=50&& beta<=100, "beta error");
         // 112
         uint denominator =  _quoteReserve + beta * _inputAmount;
         //224
         uint denominator = denominator * denominator;

         _outputAmount =  FullMath.mulDiv(inputAmount, L ,denominator);
    
        }
        return [_inputAmount, _outputAmount];



    

    //fallback

    modifier onlyMargin() {
        require(margin == msg.sender, "AMM:  margin ");
        _;
    }



}
