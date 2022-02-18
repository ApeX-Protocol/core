// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IBondPool.sol";
import "./interfaces/IPCVTreasury.sol";
import "./interfaces/IBondPriceOracle.sol";
import "../core/interfaces/IAmm.sol";
import "../core/interfaces/IERC20.sol";
import "../core/interfaces/IWETH.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/FullMath.sol";
import "../utils/Ownable.sol";

contract BondPool is IBondPool, Ownable {
    address public immutable override WETH;
    address public immutable override apeXToken;
    address public immutable override treasury;
    address public immutable override amm;
    address public override priceOracle;
    uint256 public override maxPayout;
    uint256 public override discount; // [0, 10000]
    uint256 public override vestingTerm; // in seconds
    bool public override bondPaused;

    mapping(address => Bond) private bondInfo; // stores bond information for depositor

    constructor(
        address owner_,
        address WETH_,
        address apeXToken_,
        address treasury_,
        address priceOracle_,
        address amm_,
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) {
        owner = owner_;
        WETH = WETH_;
        apeXToken = apeXToken_;
        treasury = treasury_;
        priceOracle = priceOracle_;
        amm = amm_;
        maxPayout = maxPayout_;
        discount = discount_;
        vestingTerm = vestingTerm_;
    }

    function setBondPaused(bool state) external override onlyOwner {
        bondPaused = state;
        emit BondPaused(state);
    }

    function setPriceOracle(address newOracle) external override onlyOwner {
        require(newOracle != address(0), "BondPool.setPriceOracle: ZERO_ADDRESS");
        emit PriceOracleChanged(priceOracle, newOracle);
        priceOracle = newOracle;
    }

    function setMaxPayout(uint256 maxPayout_) external override onlyOwner {
        emit MaxPayoutChanged(maxPayout, maxPayout_);
        maxPayout = maxPayout_;
    }

    function setDiscount(uint256 discount_) external override onlyOwner {
        require(discount_ <= 10000, "BondPool.setDiscount: OVER_100%");
        emit DiscountChanged(discount, discount_);
        discount = discount_;
    }

    function setVestingTerm(uint256 vestingTerm_) external override onlyOwner {
        require(vestingTerm_ >= 129600, "BondPool.setVestingTerm: MUST_BE_LONGER_THAN_36_HOURS");
        emit VestingTermChanged(vestingTerm, vestingTerm_);
        vestingTerm = vestingTerm_;
    }

    function deposit(
        address depositor,
        uint256 depositAmount,
        uint256 minPayout
    ) external override returns (uint256 payout) {
        return _depositInternal(msg.sender, depositor, depositAmount, minPayout);
    }

    function depositETH(address depositor, uint256 minPayout) external payable override returns (uint256 ethAmount, uint256 payout) {
        require(IAmm(amm).baseToken() == WETH, "BondPool.depositETH: ETH_NOT_SUPPORTED");
        ethAmount = msg.value;
        IWETH(WETH).deposit{value: ethAmount}();
        payout = _depositInternal(address(this), depositor, ethAmount, minPayout);
    }

    function redeem(address depositor) external override returns (uint256 payout) {
        Bond memory info = bondInfo[depositor];
        uint256 percentVested = percentVestedFor(depositor); // (blocks since last interaction / vesting term remaining)

        if (percentVested >= 10000) {
            // if fully vested
            delete bondInfo[depositor]; // delete user info
            payout = info.payout;
            emit BondRedeemed(depositor, payout, 0); // emit bond data
            TransferHelper.safeTransfer(apeXToken, depositor, payout);
        } else {
            // if unfinished
            // calculate payout vested
            payout = (info.payout * percentVested) / 10000;

            // store updated deposit info
            bondInfo[depositor] = Bond({
                payout: info.payout - payout,
                vesting: info.vesting - (block.timestamp - info.lastBlockTime),
                lastBlockTime: block.timestamp,
                paidAmount: info.paidAmount
            });

            emit BondRedeemed(depositor, payout, bondInfo[depositor].payout);
            TransferHelper.safeTransfer(apeXToken, depositor, payout);
        }
    }

    function bondInfoFor(address depositor) external view override returns (Bond memory) {
        return bondInfo[depositor];
    }

    // calculate how many APEX out for input amount of base token
    // marketPrice = amount / marketApeXAmount
    // bondPrice = marketPrice * (1 - discount) = amount * (1 - discount) / marketApeXAmount
    // payout = amount / bondPrice = marketApeXAmount / (1 - discount))
    function payoutFor(uint256 amount) public view override returns (uint256 payout) {
        address baseToken = IAmm(amm).baseToken();
        uint256 marketApeXAmount = IBondPriceOracle(priceOracle).quote(baseToken, amount);
        payout = marketApeXAmount * 10000 / (10000 - discount);
    }

    function percentVestedFor(address depositor) public view override returns (uint256 percentVested) {
        Bond memory bond = bondInfo[depositor];
        uint256 deltaSinceLast = block.timestamp - bond.lastBlockTime;
        uint256 vesting = bond.vesting;
        if (vesting > 0) {
            percentVested = (deltaSinceLast * 10000) / vesting;
        } else {
            percentVested = 0;
        }
    }

    function _depositInternal(
        address from,
        address depositor,
        uint256 depositAmount,
        uint256 minPayout
    ) internal returns (uint256 payout) {
        require(!bondPaused, "BondPool._depositInternal: BOND_PAUSED");
        require(depositor != address(0), "BondPool._depositInternal: ZERO_ADDRESS");
        require(depositAmount > 0, "BondPool._depositInternal: ZERO_AMOUNT");

        TransferHelper.safeTransferFrom(IAmm(amm).baseToken(), from, amm, depositAmount);
        (uint256 actualDepositAmount, , uint256 liquidity) = IAmm(amm).mint(address(this));
        require(actualDepositAmount == depositAmount, "BondPool._depositInternal: AMOUNT_NOT_MATCH");

        payout = payoutFor(depositAmount);
        require(payout >= minPayout, "BondPool._depositInternal: UNDER_MIN_LAYOUT");
        require(payout <= maxPayout, "BondPool._depositInternal: OVER_MAX_PAYOUT");
        maxPayout -= payout;
        TransferHelper.safeApprove(amm, treasury, liquidity);
        IPCVTreasury(treasury).deposit(amm, liquidity, payout);

        bondInfo[depositor] = Bond({
            payout: bondInfo[depositor].payout + payout,
            vesting: vestingTerm,
            lastBlockTime: block.timestamp,
            paidAmount: bondInfo[depositor].paidAmount + depositAmount
        });
        emit BondCreated(depositor, depositAmount, payout, block.timestamp + vestingTerm);
    }
}
