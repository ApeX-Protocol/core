pragma solidity ^0.8.0;

interface IBondPool {
    event BondCreated(uint256 deposit, uint256 payout, uint256 expires);
    event BondRedeemed(address recipient, uint256 payout, uint256 remaining);

    // Info for bond depositor
    struct Bond {
        uint256 payout;
        uint256 vesting;
        uint256 lastBlock;
        uint256 paidAmount;
    }

    function deposit(
        address depositor,
        uint256 depositAmount,
        uint256 minPayout
    ) external returns (uint256 payout);

    function redeem(address depositor) external returns (uint256 payout);

    function apeXToken() external view returns (address);

    function treasury() external view returns (address);

    function amm() external view returns (address);

    function priceOracle() external view returns (address);

    function maxPayout() external view returns (uint256);

    function discount() external view returns (uint256);

    function vestingTerm() external view returns (uint256);
    
    function bondInfoFor(address depositor) external view returns (Bond memory);
    
    function payoutFor(uint256 amount) external view returns (uint256 payout);

    function percentVestedFor(address depositor) external view returns (uint256 percentVested);
}
