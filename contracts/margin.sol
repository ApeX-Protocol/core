// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IVAmm} from "./interfaces/IVAmm.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {Math} from "./libraries/Math.sol";
import {Decimal} from "./libraries/Decimal.sol";
import {SignedDecimal} from "./libraries/SignedDecimal.sol";

import "hardhat/console.sol";

contract Margin {
    using Decimal for uint256;
    using SignedDecimal for int256;

    struct Position {
        int256 quoteSize;
        int256 baseSize;
        uint256 tradeSize;
    }

    address public factory;
    IVAmm public vAmm;
    IERC20 public baseToken;
    IERC20 public quoteToken;
    IVault public vault;
    IRouter public router;
    mapping(address => Position) public traderPositionMap;

    uint256 public initMarginRatio; //if 10, means margin ratio >= 10%
    uint256 public liquidateThreshold; //if 100, means debt ratio < 100%
    uint256 public liquidateFeeRatio; //if 1, means liquidator bot get 1% as fee

    //add $depositAmount into trader position
    event AddMargin(address trader, uint256 depositAmount);
    //withdraw $withdrawAmount from $trader position
    event RemoveMargin(address trader, uint256 withdrawAmount);
    //open position with $baseAmount($side: 0 is long, 1 is short), $quoteAmount is swapped value of vAmm
    event OpenPosition(address trader, uint8 side, uint256 baseAmount, uint256 quoteAmount);
    //close position with $quoteAmount, $baseAmount is swapped value of vAmm
    event ClosePosition(address trader, uint256 quoteAmount, uint256 baseAmount);
    //liquidate $trader's position $quoteAmount
    event Liquidate(address trader, int256 quoteSize, uint256 baseAmount, uint256 liquidateFee);

    constructor(
        address _baseToken,
        address _quoteToken,
        address _vAmm,
        address _vault,
        uint256 _initMarginRatio,
        uint256 _liquidateThreshold,
        uint256 _liquidateFeeRatio
    ) {
        factory = msg.sender;
        vAmm = IVAmm(_vAmm);
        vault = IVault(_vault);
        initMarginRatio = _initMarginRatio;
        liquidateThreshold = _liquidateThreshold;
        liquidateFeeRatio = _liquidateFeeRatio;
        baseToken = IERC20(_baseToken);
        quoteToken = IERC20(_quoteToken);
    }

    function initialize() external onlyFactory {}

    // transferring token is in router.sol
    function addMargin(address _trader, uint256 _depositAmount) external {
        require(_depositAmount > 0, ">0");
        Position memory traderPosition = traderPositionMap[_trader];

        uint256 balance = baseToken.balanceOf(address(this));
        require(_depositAmount <= balance, "wrong deposit amount");

        traderPosition.baseSize = traderPosition.baseSize.addU(_depositAmount);
        baseToken.transfer(address(vault), _depositAmount);

        _setPosition(_trader, traderPosition);
        emit AddMargin(_trader, _depositAmount);
    }

    function removeMargin(uint256 _withdrawAmount) external {
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];

        traderPosition.baseSize = traderPosition.baseSize.subU(_withdrawAmount);
        if (traderPosition.quoteSize == 0) {
            require(traderPosition.baseSize >= 0, "insufficient withdrawable");
        } else {
            // important! check position health
            _checkInitMarginRatio(traderPosition);
        }
        _setPosition(trader, traderPosition);

        vault.transferToReceiver(trader, _withdrawAmount);

        emit RemoveMargin(trader, _withdrawAmount);
    }

    function openPosition(uint8 _side, uint256 _baseAmount) external {
        require(_baseAmount != 0, "open 0");
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];
        bool isLong = _side == 0;
        bool sameDir = traderPosition.quoteSize == 0 ||
            (traderPosition.quoteSize < 0 == isLong) ||
            (traderPosition.quoteSize > 0 == !isLong);

        //swap exact base to quote
        uint256 quoteAmount = _addPositionWithVAmm(isLong, _baseAmount);

        //old: quote -10, base 11; add long 5X position 1: quote -5, base +5; new: quote -15, base 16
        //old: quote 10, base -9; add long 5X position: quote -5, base +5; new: quote 5, base -4
        //old: quote 10, base -9; add long 15X position: quote -15, base +15; new: quote -5, base 6
        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(_baseAmount);
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(_baseAmount);
        }

        if (sameDir) {
            traderPosition.tradeSize = traderPosition.tradeSize.add(_baseAmount);
        } else {
            traderPosition.tradeSize = int256(traderPosition.tradeSize).subU(_baseAmount).abs();
        }

        _checkInitMarginRatio(traderPosition);
        _setPosition(trader, traderPosition);
        emit OpenPosition(trader, _side, _baseAmount, quoteAmount);
    }

    function closePosition(uint256 _quoteAmount) external {
        //fixme
        // address trader = msg.sender;
        address trader = tx.origin;

        Position memory traderPosition = traderPositionMap[trader];
        require(traderPosition.quoteSize != 0 && _quoteAmount != 0, "position cant 0");
        require(_quoteAmount <= traderPosition.quoteSize.abs(), "above position");
        //swap exact quote to base
        bool isLong = traderPosition.quoteSize < 0;
        uint256 baseAmount = _minusPositionWithVAmm(isLong, _quoteAmount);

        //old: quote -10, base 11; close position: quote 5, base -5; new: quote -5, base 6
        //old: quote 10, base -9; close position: quote -5, base +5; new: quote 5, base -4
        if (isLong) {
            traderPosition.quoteSize = traderPosition.quoteSize.addU(_quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.subU(baseAmount);
        } else {
            traderPosition.quoteSize = traderPosition.quoteSize.subU(_quoteAmount);
            traderPosition.baseSize = traderPosition.baseSize.addU(baseAmount);
        }
        traderPosition.tradeSize = traderPosition.tradeSize.sub(baseAmount);

        _checkInitMarginRatio(traderPosition);
        _setPosition(trader, traderPosition);
        emit ClosePosition(trader, _quoteAmount, baseAmount);
    }

    function liquidate(address _trader) public {
        Position memory traderPosition = traderPositionMap[_trader];
        int256 quoteSize = traderPosition.quoteSize;
        require(traderPosition.quoteSize != 0, "position 0");
        require(canLiquidate(_trader), "not liquidatable");

        bool isLong = traderPosition.quoteSize < 0;

        //query swap exact quote to base
        uint256 baseAmount = _querySwapBaseWithVAmm(isLong, traderPosition.quoteSize.abs());

        //calc liquidate fee
        uint256 liquidateFee = baseAmount.mul(liquidateFeeRatio).div(100);
        int256 remainBaseAmount = traderPosition.baseSize.subU(baseAmount.sub(liquidateFee));
        if (remainBaseAmount > 0) {
            _minusPositionWithVAmm(isLong, traderPosition.quoteSize.abs());
            vault.transferToReceiver(_trader, uint256(remainBaseAmount));
        } else {
            //with bad debt, update directly
            if (isLong) {
                vAmm.forceSwap(
                    address(baseToken),
                    address(quoteToken),
                    remainBaseAmount.abs(),
                    traderPosition.quoteSize.abs()
                );
            } else {
                vAmm.forceSwap(
                    address(quoteToken),
                    address(baseToken),
                    traderPosition.quoteSize.abs(),
                    remainBaseAmount.abs()
                );
            }
        }
        vault.transferToReceiver(msg.sender, liquidateFee);
        traderPosition.baseSize = 0;
        traderPosition.quoteSize = 0;
        traderPosition.tradeSize = 0;
        _setPosition(_trader, traderPosition);
        emit Liquidate(_trader, quoteSize, baseAmount, liquidateFee);
    }

    function canLiquidate(address _trader) public view returns (bool) {
        Position memory traderPosition = traderPositionMap[_trader];
        uint256 debtRatio = uint256(100).sub(_calDebtRatio(traderPosition.quoteSize, traderPosition.baseSize));
        return debtRatio >= liquidateThreshold;
    }

    function _calDebtRatio(int256 quoteSize, int256 baseSize) public view returns (uint256) {
        if (quoteSize == 0) {
            return 100;
        } else if (quoteSize < 0 && baseSize == 0) {
            return 0;
        } else if (quoteSize > 0) {
            //case 1: quote 10, base -9
            //case 2: quote 10, base 1
            //calculate asset
            uint256 baseAmount = vAmm.getAccountSpecificMarkPrice().mul(quoteSize.abs());
            return Math.minU(100, baseSize.mul(100).divU(baseAmount).add(100).abs());
        } else {
            //case 1: quote -10, base 11
            //calculate debt
            uint256 baseAmount = vAmm.getAccountSpecificMarkPrice().mul(quoteSize.abs());
            uint256 ratio = baseAmount.mul(100).div(baseSize.abs());
            if (100 < ratio) {
                return 0;
            }
            return uint256(100).sub(ratio);
        }
    }

    function _calMarginRatio(int256 quoteSize, int256 baseSize) public view returns (uint256) {
        if (quoteSize == 0) {
            return 100;
        } else if (baseSize == 0 && quoteSize < 0) {
            return 0;
        } else if (quoteSize > 0) {
            //case 1: quote 10, base -9
            //case 2: quote 10, base 1
            //calculate asset
            uint256 baseAmount = vAmm.getBaseWithMarkPrice(quoteSize.abs());
            return Math.minU(100, baseSize.mul(100).divU(baseAmount).add(100).abs());
        } else {
            //case 1: quote -10, base 11
            //calculate debt
            uint256 baseAmount = vAmm.getBaseWithMarkPrice(quoteSize.abs());
            return uint256(100).sub(baseAmount.mul(100).div(baseSize.abs()));
        }
    }

    function _checkInitMarginRatio(Position memory traderPosition) internal view {
        require(
            _calMarginRatio(traderPosition.quoteSize, traderPosition.baseSize) >= initMarginRatio,
            "initMarginRatio"
        );
    }

    function _addPositionWithVAmm(bool isLong, uint256 _baseAmount) internal returns (uint256 quoteAmount) {
        address input;
        address output;
        uint256 inputAmount;
        uint256 outputAmount;
        if (isLong) {
            output = address(baseToken);
            outputAmount = _baseAmount;
        } else {
            input = address(baseToken);
            inputAmount = _baseAmount;
        }

        quoteAmount = vAmm.swap(input, output, inputAmount, outputAmount);
    }

    function _minusPositionWithVAmm(bool isLong, uint256 _quoteAmount) internal returns (uint256 baseAmount) {
        address input;
        address output;
        uint256 inputAmount;
        uint256 outputAmount;
        if (isLong) {
            output = address(quoteToken);
            outputAmount = _quoteAmount;
        } else {
            input = address(quoteToken);
            inputAmount = _quoteAmount;
        }

        baseAmount = vAmm.swap(input, output, inputAmount, outputAmount);
    }

    function _querySwapBaseWithVAmm(bool isLong, uint256 _quoteAmount) internal view returns (uint256 baseAmount) {
        address input;
        address output;
        uint256 inputAmount;
        uint256 outputAmount;
        if (isLong) {
            output = address(quoteToken);
            outputAmount = _quoteAmount;
        } else {
            input = address(quoteToken);
            inputAmount = _quoteAmount;
        }

        baseAmount = vAmm.swapQuery(input, output, inputAmount, outputAmount);
    }

    function _setPosition(address _trader, Position memory _position) internal {
        traderPositionMap[_trader] = _position;
    }

    function setInitMarginRatio(uint256 _initMarginRatio) external {
        require(_initMarginRatio >= 10, "ratio >= 10");
        initMarginRatio = _initMarginRatio;
    }

    function setLiquidateThreshold(uint256 _liquidateThreshold) external {
        require(_liquidateThreshold > 90 && _liquidateThreshold <= 100, "90 < liquidateThreshold <= 100");
        liquidateThreshold = _liquidateThreshold;
    }

    function setLiquidateFeeRatio(uint256 _liquidateFeeRatio) external {
        require(_liquidateFeeRatio > 0 && _liquidateFeeRatio <= 10, "0 < liquidateFeeRatio <= 10");
        liquidateFeeRatio = _liquidateFeeRatio;
    }

    function getWithdrawableMargin() public view returns (uint256) {
        Position memory traderPosition = traderPositionMap[msg.sender];
        uint256 baseAmount = vAmm.getBaseWithMarkPrice(traderPosition.quoteSize.abs());
        uint256 withdrawableMargin;
        if (traderPosition.quoteSize < 0) {
            withdrawableMargin = baseAmount.mul(100).div(100 - initMarginRatio).sub(traderPosition.baseSize.abs());
        } else {
            withdrawableMargin = traderPosition.baseSize.abs().mul(100).div(100 - initMarginRatio).sub(baseAmount);
        }
        return withdrawableMargin;
    }

    modifier onlyFactory() {
        require(factory == msg.sender, "factory");
        _;
    }
}
