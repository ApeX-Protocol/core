// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

interface IMargin {
    event AddMargin(address indexed trader, uint256 depositAmount);
    event RemoveMargin(address indexed trader, uint256 withdrawAmount);
    event OpenPosition(address indexed trader, uint8 side, uint256 baseAmount, uint256 quoteAmount);
    event ClosePosition(address indexed trader, uint256 quoteAmount, uint256 baseAmount);
    event Liquidate(
        address indexed liquidator,
        address indexed trader,
        uint256 quoteAmount,
        uint256 baseAmount,
        uint256 bonus
    );

    /// @notice get base token address
    function baseToken() external view returns (address);

    /// @notice get quote token address
    function quoteToken() external view returns (address);

    /// @notice get factory address
    function factory() external view returns (address);

    /// @notice get config address
    function config() external view returns (address);

    /// @notice get amm address of this margin
    function amm() external view returns (address);

    /// @notice get trader's position
    function getPosition(address trader)
        external
        view
        returns (
            int256 baseSize,
            int256 quoteSize,
            uint256 tradeSize
        );

    /// @notice get withdrawable margin of trader
    function getWithdrawable(address trader) external view returns (uint256 amount);

    /// @notice check if can liquidate this trader's position
    function canLiquidate(address trader) external view returns (bool);

    /// @notice get max open position with side and margin
    /// @param side long or short.
    /// @param margin base amount.
    function queryMaxOpenPosition(uint8 side, uint256 margin) external view returns (uint256 quoteAmount);

    /// @notice only factory can call this function
    /// @param _baseToken margin's baseToken.
    /// @param _quoteToken margin's quoteToken.
    /// @param _config config address.
    /// @param _amm amm address.
    function initialize(
        address _baseToken,
        address _quoteToken,
        address _config,
        address _amm
    ) external;

    /// @notice add margin to trader
    /// @param trader .
    /// @param depositAmount base amount to add.
    function addMargin(address trader, uint256 depositAmount) external;

    /// @notice remove margin to msg.sender
    /// @param withdrawAmount base amount to withdraw.
    function removeMargin(uint256 withdrawAmount) external;

    /// @notice open position with side and quoteAmount by msg.sender
    /// @param side long or short.
    /// @param quoteAmount quote amount.
    function openPosition(uint8 side, uint256 quoteAmount) external returns (uint256 baseAmount);

    /// @notice close msg.sender's position with quoteAmount
    /// @param quoteAmount quote amount to close.
    function closePosition(uint256 quoteAmount) external returns (uint256 baseAmount);

    /// @notice liquidate trader
    function liquidate(address trader)
        external
        returns (
            uint256 quoteAmount,
            uint256 baseAmount,
            uint256 bonus
        );
}
