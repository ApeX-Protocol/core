pragma solidity ^0.8.0;

import './interfaces/IAmm.sol';
import './interfaces/IVault.sol';
import './amm/LiquidityERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IFactory.sol';
import {IConfig} from "./interfaces/IConfig.sol";


contract Amm is IAmm, LiquidityERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public baseToken;
    address public quoteToken;
    address public config;
    address public margin;
    address public vault;

    uint112 private baseReserve;           // uses single storage slot, accessible via getReserves
    uint112 private quoteReserve;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'AMM: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _baseReserve, uint112 _quoteReserve, uint32 _blockTimestampLast) {
        _baseReserve = baseReserve;
        _quoteReserve = quoteReserve;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'AMM: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, address indexed to,  uint baseAmount, uint quoteAmount, uint liquidity);
    event Burn(address indexed sender, address indexed to,  uint baseAmount, uint quoteAmount);
    event Swap(
        address indexed inputToken,
        address indexed outputToken, 
        uint inputAmount, 
        uint outputAmount
    );
    event ForceSwap(
        address indexed inputToken, 
        address indexed outputToken, 
        uint inputAmount,
         uint outputAmount
    );

    event Rebase(uint priceBefore, uint priceAfter, uint modifyAmount);

    event Sync(uint112 reserveBase, uint112 reserveQuote);
    

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _baseToken, address _quoteToken, address _config, address _margin, address _vault) external {
        require(msg.sender == factory, 'Amm: FORBIDDEN'); // sufficient check
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        config = _config;
        margin = _margin;
        vault = _vault;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'AMM: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        baseReserve  = uint112(balance0);
        quoteReserve = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(baseReserve, quoteReserve);
    }


    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves(); // gas savings
        uint baseTokenAmount = IERC20(token0).balanceOf(address(this));
        
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
      
        if (_totalSupply == 0) {
            uint quoteAmountMinted =  getQuoteAmountByPriceOracle(baseTokenAmount);
            liquidity = Math.sqrt(baseTokenAmount.mul(quoteAmountMinted)).sub(MINIMUM_LIQUIDITY);
           _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            uint quoteAmountMinted =  getQuoteAmountByCurrentPrice(baseTokenAmount);
            liquidity = Math.min(baseTokenAmount.mul(_totalSupply) / _baseReserve, quoteAmountMinted.mul(_totalSupply) / _quoteReserve);
        }
        require(liquidity > 0, 'AMM: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);
        
        _update(_baseReserve + baseTokenAmount, _quoteReserve + quoteAmountMinted, _baseReserve, _quoteReserve);
        _safeTransfer(token0, vault, baseTokenAmount);
       
        emit Mint(msg.sender, to, amount0, amount1);
    }


    function getQuoteAmountByCurrentPrice(uint112 baseTokenAmount) internal returns(uint112 quoteTokenAmount) {

     return AMMLibary.quote( baseTokenAmount, baseReserve, quoteReserve);
    }

    function getQuoteAmountByPriceOracle(uint112 baseTokenAmount) internal returns(uint112 quoteTokenAmount) {

    // get price oracle

     return AMMLibary.quote( baseTokenAmount, baseReserve, quoteReserve);
    }

    function getSpotPrice() public returns(uint) {
       if(quoteReserve == 0 ){
           return 0;
       }
       return uint(UQ112x112.encode(baseReserve).uqdiv(quoteReserve));
       
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves(); // gas savings
        address _baseToken = baseToken;                                // gas savings
                                 
        uint vaultAmount = IERC20(_baseToken).balanceOf(address(vault));
        uint liquidity = balanceOf(address(this));

        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(_baseReserve) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(_quoteReserve) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'AMM: INSUFFICIENT_LIQUIDITY_BURNED');
        require(amount0 <= vaultAmount , "AMM: not enough base token withdraw");

        _burn(address(this), liquidity);
    
        uint balance0 = baseTokenAmount - amount0;
        uint balance1 = quoteTokenAmount - amount1;

        _update(balance0, balance1, _baseReserve, _quoteReserve);
      //  if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
      // vault withdraw
        IVault(vault).withdraw(to, amount0);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(address inputAddress, address outputAddress, uint inputAmount, uint outputAmount) external lock returns (uint256[2] memory amounts) {
        require(inputAmount > 0 || outputAmount > 0, 'AMM: INSUFFICIENT_OUTPUT_AMOUNT');

        require(inputAmount < _baseReserve && outputAmount < _quoteReserve, 'AMM: INSUFFICIENT_LIQUIDITY');

        uint _inputAmount ;
        uint _outputAmount ;
        
        if(inputAddress != 0x0 && inputAmount != 0) {
           _outputAmount =  swapInput(inputAddress, inputAmount);
           _inputAmount  =  inputAmount;
         
        } else {
            _inputAmount =  swapOutput(outputAddress, outputAmount);
            _outputAmount = outputAmout;
        }
        emit Swap( inputAddress, outputAddress, _inputAmount, _outputAmount);
        return [_inputAmount, _outputAmount ];
        
    }

 function swapQuery(address inputAddress, address outputAddress, uint inputAmount, uint outputAmount) public view  returns (uint256[2] memory amounts) {
        require(inputAmount > 0 || outputAmount > 0, 'AMM: INSUFFICIENT_OUTPUT_AMOUNT');

        require(inputAmount < _baseReserve && outputAmount < _quoteReserve, 'AMM: INSUFFICIENT_LIQUIDITY');

        uint _inputAmount ;
        uint _outputAmount ;
        
        if(inputAddress != 0x0 && inputAmount != 0) {
           _outputAmount =  swapInputQuery(inputAddress, inputAmount);
           _inputAmount  =  inputAmount;
           
        } else {
            _inputAmount =  swapOutputQuery(outputAddress, outputAmount);
            _outputAmount = outputAmout;
        }

       
        return [_inputAmount, _outputAmount];
    }

    function forceSwap(address inputToken, address outputToken, uint256 inputAmount, uint256 outputAmount ) onlyMargin external {
        require((inputToken == baseToken || inputToken == quoteToken) , " wrong input address");
        require((outputToken == baseToken || outputToken == quoteToken) , " wrong output address");
        (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves();
        if(inputToken == baseToken) {
            uint balance0 = baseReserve + inputAmount;
            uint balance1 = quoteReserve - outputAmount;  
        } 
        else {
            uint balance0 = baseReserve - outputAmount;
            uint balance1 = quoteReserve + inputAmount;

        }
        _update(balance0, balance1, _reserve0, _reserve1);
        emit ForceSwap(inputToken, outputToken, inputAmount, outputAmount);

    }


    function rebase() public  {
        require( checkPriceBias(), "price in range");
         (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves();
         uint balance0 =  _baseReserve;
         uint balance1 =balance0.mul(price) ;
         _update(balance0, balance1, _reserve0, _reserve1);
    
        emit Rebase();
    }

    function swapInput(address inputAddress, uint inputAmount) internal returns(uint amountOut) {
        require((inputAddress == baseToken || inputAddress == quoteToken) , "AMM: wrong input address");

        (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves(); // gas savings
        uint balance0;
        uint balance1;

        if(inputAddress == baseToken) {  
            amountOut=  AMMlibarary.getAmoutOut(inputAmount, _baseReserve, _quoteReserve); 
            balance0 = _baseReserve + inputAmount; 
            balance1 = _quoteReserve - amountOut; 
            // if necessary open
            // uint balance0Adjusted = balance0.mul(1000).sub(inputAmount.mul(3));
            // uint balance1Adjusted = balance1.mul(1000);
            // require(balance0Adjusted.mul(balance1Adjusted) >= uint(_baseReserve).mul(_quoteReserve).mul(1000**2), 'AMM: K');
        } else {
            amountOut=  AMMlibarary.getAmoutOut(inputAmount, _quoteReserve, _baseReserve ); 
            balance0 = _baseReserve  - amountOut; 
            balance1 = _quoteReserve + inputAmount ; 
        }
        _update(balance0, balance1, _baseReserve, _quoteReserve);
    }

     
    function swapOutput( address outputAddress, uint outputAmount) internal  returns(uint amountIn) {
        require((outputAddress == baseToken || outputAddress == quoteToken) , "AMM: wrong output address");
        uint balance0;
        uint balance1;
        (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves(); // gas savings
        if(outputAddress == baseToken) {
            amountIn=  AMMlibarary.getAmoutIn(outputAmount,_quoteReserve, _baseReserve ); 
            balance0 = _baseReserve -  outputAmount; 
            balance1 = _quoteReserve + amountIn; 
        
        } else {
            amountIn =  AMMlibarary.getAmoutIn(outputAmount, _baseReserve, _quoteReserve ); 
            balance0 = _baseReserve +  amountIn; 
            balance1 = _quoteReserve - outputAmount; 
        }
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    function swapInputQuery(address inputAddress, uint inputAmount)  internal returns(uint amountOut) {
        require((inputAddress == baseToken || inputAddress == quoteToken) , "AMM: wrong input address");

        (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves(); // gas savings
        
        if(inputAddress == baseToken) {  
            amountOut=  AMMlibarary.getAmoutOut(inputAmount, _baseReserve, _quoteReserve); 
        } else {
            amountOut=  AMMlibarary.getAmoutOut(inputAmount, _quoteReserve, _baseReserve ); 
        }
       
    }

     function swapOutputQuery( address outputAddress, uint outputAmount) internal  returns(uint amountIn) {
        require((outputAddress == baseToken || outputAddress == quoteToken) , "AMM: wrong output address");
        
        uint amountIn;
        (uint112 _baseReserve, uint112 _quoteReserve,) = getReserves(); // gas savings
       
        if(outputAddress == baseToken) {
            amountIn=  AMMlibarary.getAmoutIn(outputAmount,_quoteReserve, _baseReserve ); 
        } else {
            amountIn =  AMMlibarary.getAmoutIn(outputAmount, _baseReserve, _quoteReserve ); 
        }
    
    }



    // force balances to match reserves
    // function skim(address to) external lock {
    //     address _token0 = token0; // gas savings
    //     address _token1 = token1; // gas savings
    //     _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
    //     _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    // }

    // // force reserves to match balances
    // function sync() external lock {
    //     _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    // }

    //fallback
}
