// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title The interface for a bond pool
/// @notice A bond pool always be created by bond pool factory
interface IBondPool {
    /// @notice Emitted when a user finish deposit for a bond
    /// @param depositor User's address
    /// @param deposit The base token amount paid by sender
    /// @param payout The amount of apeX token for this bond
    /// @param expires The bonding's expire timestamp
    event BondCreated(address depositor, uint256 deposit, uint256 payout, uint256 expires);

    /// @notice Emitted when a redeem finish
    /// @param depositor Bonder's address
    /// @param payout The amount of apeX redeemed
    /// @param remaining The amount of apeX remaining in the bond
    event BondRedeemed(address depositor, uint256 payout, uint256 remaining);

    event BondPaused(bool state);
    event PriceOracleChanged(address indexed oldOracle, address indexed newOracle);
    event MaxPayoutChanged(uint256 oldMaxPayout, uint256 newMaxPayout);
    event DiscountChanged(uint256 oldDiscount, uint256 newDiscount);
    event VestingTermChanged(uint256 oldVestingTerm, uint256 newVestingTerm);

    // Info for bond depositor
    struct Bond {
        uint256 payout; // apeX token amount
        uint256 vesting; // bonding term, in seconds
        uint256 lastBlockTime; // last action time
        uint256 paidAmount; // base token paid
    }

    /// @notice Set bond open or pause
    function setBondPaused(bool state) external;

    /// @notice Set a new price oracle
    function setPriceOracle(address newOracle) external;

    /// @notice Only owner can set this
    function setMaxPayout(uint256 maxPayout_) external;

    /// @notice Only owner can set this
    function setDiscount(uint256 discount_) external;

    /// @notice Only owner can set this
    function setVestingTerm(uint256 vestingTerm_) external;

    /// @notice User deposit the base token to make a bond for the apeX token
    function deposit(
        address depositor,
        uint256 depositAmount,
        uint256 minPayout
    ) external returns (uint256 payout);

    /// @notice User deposit ETH to make a bond for the apeX token
    function depositETH(address depositor, uint256 minPayout) external payable returns (uint256 ethAmount, uint256 payout);

    /// @notice For user to redeem the apeX
    function redeem(address depositor) external returns (uint256 payout);

    /// @notice WETH address
    function WETH() external view returns (address);

    /// @notice ApeXToken address
    function apeXToken() external view returns (address);

    /// @notice PCV treasury contract address
    function treasury() external view returns (address);

    /// @notice Amm pool address
    function amm() external view returns (address);

    /// @notice Price oracle address
    function priceOracle() external view returns (address);

    /// @notice Left total amount of apeX token for bonding in this bond pool
    function maxPayout() external view returns (uint256);

    /// @notice Discount percent for bonding
    function discount() external view returns (uint256);

    /// @notice Bonding term in seconds, at least 129600 = 36 hours
    function vestingTerm() external view returns (uint256);

    /// @notice If is true, the bond is paused
    function bondPaused() external view returns (bool);

    /// @notice Get depositor's bond info
    function bondInfoFor(address depositor) external view returns (Bond memory);

    /// @notice Calculate how many apeX payout for input base token amount
    function payoutFor(uint256 amount) external view returns (uint256 payout);

    /// @notice Get the percent of apeX redeemable
    function percentVestedFor(address depositor) external view returns (uint256 percentVested);
}
