pragma solidity ^0.8.0;

import "./LiquidityERC20.sol";
import "./interfaces/IAmmFactory.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IMarginFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IPairFactory.sol";
import "../utils/Reentrant.sol";
import "../libraries/UQ112x112.sol";
import "../libraries/Math.sol";
import "../libraries/FullMath.sol";

contract Amm is IAmm, LiquidityERC20, Reentrant {
    using UQ112x112 for uint224;

    uint256 public constant override MINIMUM_LIQUIDITY = 10**3;

    address public immutable override factory;
    address public override config;
    address public override baseToken;
    address public override quoteToken;
    address public override margin;

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;
    uint256 public kLast;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    uint112 private baseReserve; // uses single storage slot, accessible via getReserves
    uint112 private quoteReserve; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    modifier onlyMargin() {
        require(margin == msg.sender, "Amm: ONLY_MARGIN");
        _;
    }

    constructor() {
        factory = msg.sender;
    }

    function initialize(
        address baseToken_,
        address quoteToken_,
        address margin_
    ) external override {
        require(msg.sender == factory, "Amm.initialize: FORBIDDEN"); // sufficient check
        baseToken = baseToken_;
        quoteToken = quoteToken_;
        margin = margin_;
        config = IAmmFactory(factory).config();
    }

    function mint(address to)
        external
        override
        nonReentrant
        returns (
            uint256 baseAmount,
            uint256 quoteAmount,
            uint256 liquidity
        )
    {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        baseAmount = IERC20(baseToken).balanceOf(address(this));
        require(baseAmount > 0, "Amm.mint: ZERO_BASE_AMOUNT");

        bool feeOn = _mintFee(_baseReserve, _quoteReserve);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee

        // forward  baseAmount -> quoteAmount
        if (_totalSupply == 0) {
            quoteAmount = IPriceOracle(IConfig(config).priceOracle()).quote(baseToken, quoteToken, baseAmount);
            require(quoteAmount > 0, "Amm.mint: INSUFFICIENT_QUOTE_AMOUNT");
            liquidity = Math.sqrt(baseAmount * quoteAmount) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            quoteAmount = (baseAmount * _quoteReserve) / _baseReserve;
            liquidity = Math.min(
                (baseAmount * _totalSupply) / _baseReserve,
                (quoteAmount * _totalSupply) / _quoteReserve
            );
        }
        require(liquidity > 0, "Amm.mint: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(_baseReserve + baseAmount, _quoteReserve + quoteAmount, _baseReserve, _quoteReserve);
        if (feeOn) kLast = uint256(baseReserve) * quoteReserve;

        _safeTransfer(baseToken, margin, baseAmount);

        //todo forward
        IVault(margin).deposit(msg.sender, baseAmount);

        emit Mint(msg.sender, to, baseAmount, quoteAmount, liquidity);
    }

    function burn(address to)
        external
        override
        nonReentrant
        returns (
            uint256 baseAmount,
            uint256 quoteAmount,
            uint256 liquidity
        )
    {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_baseReserve, _quoteReserve);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        baseAmount = (liquidity * _baseReserve) / _totalSupply; // using balances ensures pro-rata distribution
        quoteAmount = (liquidity * _quoteReserve) / _totalSupply; // using balances ensures pro-rata distribution
        require(baseAmount > 0 && quoteAmount > 0, "Amm.burn: INSUFFICIENT_LIQUIDITY_BURNED");
        _burn(address(this), liquidity);
        _update(_baseReserve - baseAmount, _quoteReserve - quoteAmount, _baseReserve, _quoteReserve);
        if (feeOn) kLast = uint256(baseReserve) * quoteReserve;

        //forward
        IVault(margin).withdraw(msg.sender, to, baseAmount);
        emit Burn(msg.sender, to, baseAmount, quoteAmount, liquidity);
    }

    function swap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external override nonReentrant onlyMargin returns (uint256[2] memory amounts) {
        // todo onlymargin
        uint256[2] memory reserves;
        (reserves, amounts) = _estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        _update(reserves[0], reserves[1], baseReserve, quoteReserve);
        emit Swap(inputToken, outputToken, amounts[0], amounts[1]);
    }

    function forceSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external override nonReentrant onlyMargin {
        require(inputToken == baseToken || inputToken == quoteToken, "Amm.forceSwap: WRONG_INPUT_TOKEN");
        require(outputToken == baseToken || outputToken == quoteToken, "Amm.forceSwap: WRONG_OUTPUT_TOKEN");
        require(inputToken != outputToken, "Amm.forceSwap: SAME_TOKENS");
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        uint256 reserve0;
        uint256 reserve1;
        if (inputToken == baseToken) {
            reserve0 = _baseReserve + inputAmount;
            reserve1 = _quoteReserve - outputAmount;
        } else {
            reserve0 = _baseReserve - outputAmount;
            reserve1 = _quoteReserve + inputAmount;
        }
        _update(reserve0, reserve1, _baseReserve, _quoteReserve);
        emit ForceSwap(inputToken, outputToken, inputAmount, outputAmount);
    }

    function rebase() external override nonReentrant returns (uint256 quoteReserveAfter) {
        require(msg.sender == tx.origin, "Amm.rebase: ONLY_EOA");
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        // forward
        quoteReserveAfter = IPriceOracle(IConfig(config).priceOracle()).quote(baseToken, quoteToken, _baseReserve);
        uint256 gap = IConfig(config).rebasePriceGap();
        require(
            quoteReserveAfter * 100 >= uint256(_quoteReserve) * (100 + gap) ||
                quoteReserveAfter * 100 <= uint256(_quoteReserve) * (100 - gap),
            "Amm.rebase: NOT_BEYOND_PRICE_GAP"
        );
        _update(_baseReserve, quoteReserveAfter, _baseReserve, _quoteReserve);
        emit Rebase(_quoteReserve, quoteReserveAfter);
    }

    function estimateSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view override returns (uint256[2] memory amounts) {
        (, amounts) = _estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
    }

    function estimateSwapWithMarkPrice(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external view override returns (uint256[2] memory amounts) {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        uint256 quoteAmount;
        uint256 baseAmount;
        bool dir;
        if (inputAmount != 0 && inputToken == quoteToken) {
            //short
            quoteAmount = inputAmount;
            dir = false;
        } else {
            //long
            quoteAmount = outputAmount;
            dir = true;
        }

        // price = (sqrt(y/x)+ betal * deltaY/L).**2;
        // deltaX = deltaY/price
        // deltaX = (deltaY * L)/(y + betal * deltaY)**2

        uint256 L = uint256(_baseReserve) * uint256(_quoteReserve);
        uint8 beta = IConfig(config).beta();
        require(beta >= 50 && beta <= 100, "beta error");

        //112
        uint256 denominator;

        if (dir) {
            //long
            denominator = (_quoteReserve - (beta * quoteAmount) / 100);
        } else {
            //short
            denominator = (_quoteReserve + (beta * quoteAmount) / 100);
        }

        //224
        denominator = denominator * denominator;
        baseAmount = FullMath.mulDiv(quoteAmount, L, denominator);
        return inputAmount == 0 ? [baseAmount, quoteAmount] : [quoteAmount, baseAmount];
    }

    function getReserves()
        public
        view
        override
        returns (
            uint112 reserveBase,
            uint112 reserveQuote,
            uint32 blockTimestamp
        )
    {
        reserveBase = baseReserve;
        reserveQuote = quoteReserve;
        blockTimestamp = blockTimestampLast;
    }

    function _estimateSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) internal view returns (uint256[2] memory reserves, uint256[2] memory amounts) {
        require(inputToken == baseToken || inputToken == quoteToken, "Amm._estimateSwap: WRONG_INPUT_TOKEN");
        require(outputToken == baseToken || outputToken == quoteToken, "Amm._estimateSwap: WRONG_OUTPUT_TOKEN");
        require(inputToken != outputToken, "Amm._estimateSwap: SAME_TOKENS");
        require(inputAmount > 0 || outputAmount > 0, "Amm._estimateSwap: INSUFFICIENT_AMOUNT");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        uint256 reserve0;
        uint256 reserve1;
        if (inputAmount > 0 && inputToken != address(0)) {
            // swapOut
            if (inputToken == baseToken) {
                outputAmount = _getAmountOut(inputAmount, _baseReserve, _quoteReserve);
                reserve0 = _baseReserve + inputAmount;
                reserve1 = _quoteReserve - outputAmount;
            } else {
                outputAmount = _getAmountOut(inputAmount, _quoteReserve, _baseReserve);
                reserve0 = _baseReserve - outputAmount;
                reserve1 = _quoteReserve + inputAmount;
            }
        } else {
            //swapIn
            if (outputToken == baseToken) {
                inputAmount = _getAmountIn(outputAmount, _quoteReserve, _baseReserve);
                reserve0 = _baseReserve - outputAmount;
                reserve1 = _quoteReserve + inputAmount;
            } else {
                inputAmount = _getAmountIn(outputAmount, _baseReserve, _quoteReserve);
                reserve0 = _baseReserve + inputAmount;
                reserve1 = _quoteReserve - outputAmount;
            }
        }
        reserves = [reserve0, reserve1];
        amounts = [inputAmount, outputAmount];
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "Amm._getAmountOut: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Amm._getAmountOut: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 999;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "Amm._getAmountIn: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "Amm._getAmountIn: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 999;
        amountIn = (numerator / denominator) + 1;
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 reserve0, uint112 reserve1) private returns (bool feeOn) {
        address feeTo = IAmmFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(reserve0) * reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast);
                    //todo
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function _update(
        uint256 baseReserveNew,
        uint256 quoteReserveNew,
        uint112 baseReserveOld,
        uint112 quoteReserveOld
    ) private {
        require(baseReserveNew <= type(uint112).max && quoteReserveNew <= type(uint112).max, "AMM._update: OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && baseReserveOld != 0 && quoteReserveOld != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(quoteReserveOld).uqdiv(baseReserveOld)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(baseReserveOld).uqdiv(quoteReserveOld)) * timeElapsed;
        }
        baseReserve = uint112(baseReserveNew);
        quoteReserve = uint112(quoteReserveNew);
        blockTimestampLast = blockTimestamp;
        emit Sync(baseReserve, quoteReserve);
    }

    function _safeTransfer(
        address token,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "AMM._safeTransfer: TRANSFER_FAILED");
    }
}
