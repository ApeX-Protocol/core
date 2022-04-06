// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./LiquidityERC20.sol";
import "./interfaces/IAmmFactory.sol";
import "./interfaces/IConfig.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IMarginFactory.sol";
import "./interfaces/IAmm.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IMargin.sol";
import "./interfaces/IPairFactory.sol";
import "../utils/Reentrant.sol";
import "../libraries/UQ112x112.sol";
import "../libraries/Math.sol";
import "../libraries/FullMath.sol";
import "../libraries/ChainAdapter.sol";
import "../libraries/SignedMath.sol";

contract Amm is IAmm, LiquidityERC20, Reentrant {
    using UQ112x112 for uint224;
    using SignedMath for int256;

    uint256 public constant override MINIMUM_LIQUIDITY = 10**3;

    address public immutable override factory;
    address public override config;
    address public override baseToken;
    address public override quoteToken;
    address public override margin;

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;

    uint256 public kLast;
    uint256 public override lastPrice;

    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));
    uint112 private baseReserve; // uses single storage slot, accessible via getReserves
    uint112 private quoteReserve; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast;
    uint256 private lastBlockNumber;
    uint256 private rebaseTimestampLast;

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

    /// @notice add liquidity
    /// @dev  calculate the liquidity according to the real baseReserve.
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
        // only router can add liquidity
        require(IConfig(config).routerMap(msg.sender), "Amm.mint: FORBIDDEN");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings

        // get real baseReserve
        uint256 realBaseReserve = getRealBaseReserve();

        baseAmount = IERC20(baseToken).balanceOf(address(this));
        require(baseAmount > 0, "Amm.mint: ZERO_BASE_AMOUNT");

        bool feeOn = _mintFee(_baseReserve, _quoteReserve);
        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee

        if (_totalSupply == 0) {
            (quoteAmount, ) = IPriceOracle(IConfig(config).priceOracle()).quote(baseToken, quoteToken, baseAmount);

            require(quoteAmount > 0, "Amm.mint: INSUFFICIENT_QUOTE_AMOUNT");
            liquidity = Math.sqrt(baseAmount * quoteAmount) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            quoteAmount = (baseAmount * _quoteReserve) / _baseReserve;

            // realBaseReserve
            liquidity = (baseAmount * _totalSupply) / realBaseReserve;
        }
        require(liquidity > 0, "Amm.mint: INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        //price check  0.1%
        require(
            (_baseReserve + baseAmount) * _quoteReserve * 999 <= (_quoteReserve + quoteAmount) * _baseReserve * 1000,
            "Amm.mint: PRICE_BEFORE_AND_AFTER_MUST_BE_THE_SAME"
        );
        require(
            (_quoteReserve + quoteAmount) * _baseReserve * 1000 <= (_baseReserve + baseAmount) * _quoteReserve * 1001,
            "Amm.mint: PRICE_BEFORE_AND_AFTER_MUST_BE_THE_SAME"
        );

        _update(_baseReserve + baseAmount, _quoteReserve + quoteAmount, _baseReserve, _quoteReserve, false);

        if (feeOn) kLast = uint256(baseReserve) * quoteReserve;

        _safeTransfer(baseToken, margin, baseAmount);
        IVault(margin).deposit(msg.sender, baseAmount);

        emit Mint(msg.sender, to, baseAmount, quoteAmount, liquidity);
    }

    /// @notice add liquidity
    /// @dev  calculate the liquidity according to the real baseReserve.
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
        // only router can burn liquidity
        require(IConfig(config).routerMap(msg.sender), "Amm.mint: FORBIDDEN");
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        liquidity = balanceOf[address(this)];

        // get real baseReserve
        uint256 realBaseReserve = getRealBaseReserve();

        // calculate the fee
        bool feeOn = _mintFee(_baseReserve, _quoteReserve);

        uint256 _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        baseAmount = (liquidity * realBaseReserve) / _totalSupply;
        // quoteAmount = (liquidity * _quoteReserve) / _totalSupply; // using balances ensures pro-rata distribution
        quoteAmount = (baseAmount * _quoteReserve) / _baseReserve;
        require(baseAmount > 0 && quoteAmount > 0, "Amm.burn: INSUFFICIENT_LIQUIDITY_BURNED");

        // gurantee the net postion close and total position(quote) in a tolerant sliappage after remove liquidity
        maxWithdrawCheck(uint256(_quoteReserve), quoteAmount);

        require(
            (_baseReserve - baseAmount) * _quoteReserve * 999 <= (_quoteReserve - quoteAmount) * _baseReserve * 1000,
            "Amm.burn: PRICE_BEFORE_AND_AFTER_MUST_BE_THE_SAME"
        );
        require(
            (_quoteReserve - quoteAmount) * _baseReserve * 1000 <= (_baseReserve - baseAmount) * _quoteReserve * 1001,
            "Amm.burn: PRICE_BEFORE_AND_AFTER_MUST_BE_THE_SAME"
        );

        _burn(address(this), liquidity);
        _update(_baseReserve - baseAmount, _quoteReserve - quoteAmount, _baseReserve, _quoteReserve, false);
        if (feeOn) kLast = uint256(baseReserve) * quoteReserve;

        IVault(margin).withdraw(msg.sender, to, baseAmount);
        emit Burn(msg.sender, to, baseAmount, quoteAmount, liquidity);
    }

    function maxWithdrawCheck(uint256 quoteReserve_, uint256 quoteAmount) public view {
        int256 quoteTokenOfNetPosition = IMargin(margin).netPosition();
        uint256 quoteTokenOfTotalPosition = IMargin(margin).totalPosition();
        uint256 lpWithdrawThresholdForNet = IConfig(config).lpWithdrawThresholdForNet();
        uint256 lpWithdrawThresholdForTotal = IConfig(config).lpWithdrawThresholdForTotal();

        require(
            quoteTokenOfNetPosition.abs() * 100 <= (quoteReserve_ - quoteAmount) * lpWithdrawThresholdForNet,
            "Amm.burn: TOO_LARGE_LIQUIDITY_WITHDRAW_FOR_NET_POSITION"
        );
        require(
            quoteTokenOfTotalPosition * 100 <= (quoteReserve_ - quoteAmount) * lpWithdrawThresholdForTotal,
            "Amm.burn: TOO_LARGE_LIQUIDITY_WITHDRAW_FOR_TOTAL_POSITION"
        );
    }

    function getRealBaseReserve() public view returns (uint256 realBaseReserve) {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();

        int256 quoteTokenOfNetPosition = IMargin(margin).netPosition();

        require(int256(uint256(_quoteReserve)) + quoteTokenOfNetPosition <= 2**112, "Amm.mint:NetPosition_VALUE_WRONT");

        uint256 baseTokenOfNetPosition;

        if (quoteTokenOfNetPosition == 0) {
            return uint256(_baseReserve);
        }

        uint256[2] memory result;
        if (quoteTokenOfNetPosition < 0) {
            // long  （+， -）
            result = estimateSwap(baseToken, quoteToken, 0, quoteTokenOfNetPosition.abs());
            baseTokenOfNetPosition = result[0];

            realBaseReserve = uint256(_baseReserve) + baseTokenOfNetPosition;
        } else {
            //short  （-， +）
            result = estimateSwap(quoteToken, baseToken, quoteTokenOfNetPosition.abs(), 0);
            baseTokenOfNetPosition = result[1];

            realBaseReserve = uint256(_baseReserve) - baseTokenOfNetPosition;
        }
    }

    /// @notice
    function swap(
        address trader,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external override nonReentrant onlyMargin returns (uint256[2] memory amounts) {
        uint256[2] memory reserves;
        (reserves, amounts) = _estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
        //check trade slippage
        _checkTradeSlippage(reserves[0], reserves[1], baseReserve, quoteReserve);
        _update(reserves[0], reserves[1], baseReserve, quoteReserve, false);

        emit Swap(trader, inputToken, outputToken, amounts[0], amounts[1]);
    }

    /// @notice  use in the situation  of forcing closing position
    function forceSwap(
        address trader,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) external override nonReentrant onlyMargin {
        require(inputToken == baseToken || inputToken == quoteToken, "Amm.forceSwap: WRONG_INPUT_TOKEN");
        require(outputToken == baseToken || outputToken == quoteToken, "Amm.forceSwap: WRONG_OUTPUT_TOKEN");
        require(inputToken != outputToken, "Amm.forceSwap: SAME_TOKENS");
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        bool feeOn = _mintFee(_baseReserve, _quoteReserve);

        uint256 reserve0;
        uint256 reserve1;
        if (inputToken == baseToken) {
            reserve0 = _baseReserve + inputAmount;
            reserve1 = _quoteReserve - outputAmount;
        } else {
            reserve0 = _baseReserve - outputAmount;
            reserve1 = _quoteReserve + inputAmount;
        }

        _update(reserve0, reserve1, _baseReserve, _quoteReserve, true);
        if (feeOn) kLast = uint256(baseReserve) * quoteReserve;

        emit ForceSwap(trader, inputToken, outputToken, inputAmount, outputAmount);
    }

    /// @notice invoke when price gap is larger than "gap" percent;
    /// @notice gap is in config contract
    function rebase() external override nonReentrant returns (uint256 quoteReserveAfter) {
        require(msg.sender == tx.origin, "Amm.rebase: ONLY_EOA");
        uint256 interval = IConfig(config).rebaseInterval();
        require(block.timestamp - rebaseTimestampLast >= interval, "Amm.rebase: NOT_REACH_NEXT_REBASE_TIME");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        bool feeOn = _mintFee(_baseReserve, _quoteReserve);

        uint256 quoteReserveFromInternal;
        (uint256 quoteReserveFromExternal, uint8 priceSource) = IPriceOracle(IConfig(config).priceOracle()).quote(
            baseToken,
            quoteToken,
            _baseReserve
        );
        if (priceSource == 0) {
            // external price use UniswapV3Twap, internal price use ammTwap
            quoteReserveFromInternal = IPriceOracle(IConfig(config).priceOracle()).quoteFromAmmTwap(
                address(this),
                _baseReserve
            );
        } else {
            // otherwise, use lastPrice as internal price
            quoteReserveFromInternal = (lastPrice * _baseReserve) / 2**112;
        }

        uint256 gap = IConfig(config).rebasePriceGap();
        require(
            quoteReserveFromExternal * 100 >= quoteReserveFromInternal * (100 + gap) ||
                quoteReserveFromExternal * 100 <= quoteReserveFromInternal * (100 - gap),
            "Amm.rebase: NOT_BEYOND_PRICE_GAP"
        );

        quoteReserveAfter = quoteReserveFromExternal;

        rebaseTimestampLast = uint32(block.timestamp % 2**32);
        _update(_baseReserve, quoteReserveAfter, _baseReserve, _quoteReserve, true);
        if (feeOn) kLast = uint256(baseReserve) * quoteReserve;

        emit Rebase(_quoteReserve, quoteReserveAfter, _baseReserve, quoteReserveFromInternal, quoteReserveFromExternal);
    }

    function collectFee() external override returns (bool feeOn) {
        require(IConfig(config).routerMap(msg.sender), "Amm.collectFee: FORBIDDEN");

        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves();
        feeOn = _mintFee(_baseReserve, _quoteReserve);
        if (feeOn) kLast = uint256(_baseReserve) * _quoteReserve;
    }

    /// notice view method for estimating swap
    function estimateSwap(
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount
    ) public view override returns (uint256[2] memory amounts) {
        (, amounts) = _estimateSwap(inputToken, outputToken, inputAmount, outputAmount);
    }

    //query max withdraw liquidity
    function getTheMaxBurnLiquidity() public view override returns (uint256 maxLiquidity) {
        (uint112 _baseReserve, uint112 _quoteReserve, ) = getReserves(); // gas savings
        // get real baseReserve
        uint256 realBaseReserve = getRealBaseReserve();
        int256 quoteTokenOfNetPosition = IMargin(margin).netPosition();
        uint256 quoteTokenOfTotalPosition = IMargin(margin).totalPosition();
        uint256 _totalSupply = totalSupply + getFeeLiquidity();

        uint256 lpWithdrawThresholdForNet = IConfig(config).lpWithdrawThresholdForNet();
        uint256 lpWithdrawThresholdForTotal = IConfig(config).lpWithdrawThresholdForTotal();

        //  for net position  case
        uint256 maxQuoteLeftForNet = (quoteTokenOfNetPosition.abs() * 100) / lpWithdrawThresholdForNet;
        uint256 maxWithdrawQuoteAmountForNet;
        if (_quoteReserve > maxQuoteLeftForNet) {
            maxWithdrawQuoteAmountForNet = _quoteReserve - maxQuoteLeftForNet;
        }

        //  for total position  case
        uint256 maxQuoteLeftForTotal = (quoteTokenOfTotalPosition * 100) / lpWithdrawThresholdForTotal;
        uint256 maxWithdrawQuoteAmountForTotal;
        if (_quoteReserve > maxQuoteLeftForTotal) {
            maxWithdrawQuoteAmountForTotal = _quoteReserve - maxQuoteLeftForTotal;
        }

        uint256 maxWithdrawBaseAmount;
        // use the min quote amount;
        if (maxWithdrawQuoteAmountForNet > maxWithdrawQuoteAmountForTotal) {
            maxWithdrawBaseAmount = (maxWithdrawQuoteAmountForTotal * _baseReserve) / _quoteReserve;
        } else {
            maxWithdrawBaseAmount = (maxWithdrawQuoteAmountForNet * _baseReserve) / _quoteReserve;
        }

        maxLiquidity = (maxWithdrawBaseAmount * _totalSupply) / realBaseReserve;
    }

    function getFeeLiquidity() public view override returns (uint256) {
        address feeTo = IAmmFactory(factory).feeTo();
        bool feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        uint256 liquidity;
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(baseReserve) * quoteReserve);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply * (rootK - rootKLast);

                    uint256 feeParameter = IConfig(config).feeParameter();
                    uint256 denominator = (rootK * feeParameter) / 100 + rootKLast;
                    liquidity = numerator / denominator;
                }
            }
        }
        return liquidity;
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

    function _checkTradeSlippage(
        uint256 baseReserveNew,
        uint256 quoteReserveNew,
        uint112 baseReserveOld,
        uint112 quoteReserveOld
    ) internal view {
        // check trade slippage for every transaction
        uint256 numerator = quoteReserveNew * baseReserveOld * 100;
        uint256 demominator = baseReserveNew * quoteReserveOld;
        uint256 tradingSlippage = IConfig(config).tradingSlippage();
        require(
            (numerator < (100 + tradingSlippage) * demominator) && (numerator > (100 - tradingSlippage) * demominator),
            "AMM._update: TRADINGSLIPPAGE_TOO_LARGE_THAN_LAST_TRANSACTION"
        );
        require(
            (quoteReserveNew * 100 < ((100 + tradingSlippage) * baseReserveNew * lastPrice) / 2**112) &&
                (quoteReserveNew * 100 > ((100 - tradingSlippage) * baseReserveNew * lastPrice) / 2**112),
            "AMM._update: TRADINGSLIPPAGE_TOO_LARGE_THAN_LAST_BLOCK"
        );
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
            // swapInput
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
            // swapOutput
            if (outputToken == baseToken) {
                require(outputAmount < _baseReserve, "AMM._estimateSwap: INSUFFICIENT_LIQUIDITY");
                inputAmount = _getAmountIn(outputAmount, _quoteReserve, _baseReserve);
                reserve0 = _baseReserve - outputAmount;
                reserve1 = _quoteReserve + inputAmount;
            } else {
                require(outputAmount < _quoteReserve, "AMM._estimateSwap: INSUFFICIENT_LIQUIDITY");
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

                    uint256 feeParameter = IConfig(config).feeParameter();
                    uint256 denominator = (rootK * feeParameter) / 100 + rootKLast;
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
        uint112 quoteReserveOld,
        bool isRebaseOrForceSwap
    ) private {
        require(baseReserveNew <= type(uint112).max && quoteReserveNew <= type(uint112).max, "AMM._update: OVERFLOW");

        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        // last price means last block price.
        if (timeElapsed > 0 && baseReserveOld != 0 && quoteReserveOld != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(quoteReserveOld).uqdiv(baseReserveOld)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(baseReserveOld).uqdiv(quoteReserveOld)) * timeElapsed;
            // update twap
            IPriceOracle(IConfig(config).priceOracle()).updateAmmTwap(address(this));
        }

        uint256 blockNumberDelta = ChainAdapter.blockNumber() - lastBlockNumber;
        //every arbi block number calculate
        if (blockNumberDelta > 0 && baseReserveOld != 0) {
            lastPrice = uint256(UQ112x112.encode(quoteReserveOld).uqdiv(baseReserveOld));
        }

        //set the last price to current price for rebase may cause price gap oversize the tradeslippage.
        if ((lastPrice == 0 && baseReserveNew != 0) || isRebaseOrForceSwap) {
            lastPrice = uint256(UQ112x112.encode(uint112(quoteReserveNew)).uqdiv(uint112(baseReserveNew)));
        }

        baseReserve = uint112(baseReserveNew);
        quoteReserve = uint112(quoteReserveNew);

        lastBlockNumber = ChainAdapter.blockNumber();
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
