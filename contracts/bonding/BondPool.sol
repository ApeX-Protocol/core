// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IBondPool.sol";
import "./interfaces/IPCVTreasury.sol";
import "../core/interfaces/IAmm.sol";
import "../core/interfaces/IERC20.sol";
import "../core/interfaces/IPriceOracle.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/FullMath.sol";
import "../utils/Ownable.sol";

contract BondPool is IBondPool, Ownable {
    address public immutable override apeXToken;
    address public immutable override treasury;
    address public immutable override priceOracle;
    address public immutable override amm;
    uint256 public override maxPayout;
    uint256 public override discount; // [0, 10000]
    uint256 public override vestingTerm; // in seconds

    mapping(address => Bond) private bondInfo; // stores bond information for depositor

    constructor(
        address apeXToken_,
        address treasury_,
        address priceOracle_,
        address amm_,
        uint256 maxPayout_,
        uint256 discount_,
        uint256 vestingTerm_
    ) {
        owner = msg.sender;
        require(apeXToken_ != address(0), "BondPool: ZERO_ADDRESS");
        apeXToken = apeXToken_;
        require(treasury_ != address(0), "BondPool: ZERO_ADDRESS");
        treasury = treasury_;
        require(priceOracle_ != address(0), "BondPool: ZERO_ADDRESS");
        priceOracle = priceOracle_;
        require(amm_ != address(0), "BondPool: ZERO_ADDRESS");
        amm = amm_;
        maxPayout = maxPayout_;
        require(discount_ <= 10000, "BondPool: DISCOUNT_OVER_100%");
        discount = discount_;
        require(vestingTerm_ >= 129600, "BondPool: MUST_BE_LONGER_THAN_36_HOURS");
        vestingTerm = vestingTerm_;
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
        require(depositor != address(0), "BondPool.deposit: ZERO_ADDRESS");
        require(depositAmount > 0, "BondPool.deposit: ZERO_AMOUNT");

        TransferHelper.safeTransferFrom(IAmm(amm).baseToken(), msg.sender, amm, depositAmount);
        (uint256 actualDepositAmount, , uint256 liquidity) = IAmm(amm).mint(address(this));
        require(actualDepositAmount == depositAmount, "BondPool.deposit: AMOUNT_NOT_MATCH");

        payout = payoutFor(depositAmount);
        require(payout >= minPayout, "BondPool.deposit: UNDER_MIN_LAYOUT");
        require(payout <= maxPayout, "BondPool.deposit: OVER_MAX_PAYOUT");
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
    function payoutFor(uint256 amount) public view override returns (uint256 payout) {
        address baseToken = IAmm(amm).baseToken();
        uint256 marketApeXAmount = IPriceOracle(priceOracle).quote(baseToken, apeXToken, amount);
        uint256 denominator = (marketApeXAmount * (10000 - discount)) / 10000;
        payout = FullMath.mulDiv(amount, amount, denominator);
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
}
