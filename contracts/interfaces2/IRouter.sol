pragma solidity ^0.8.0;

interface IRouter {
    function factory() external pure returns (address);

    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint baseAmount,
        uint quoteAmountMin,
        uint deadline,
        bool autoStake
    ) external returns (uint quoteAmount, uint liquidity);

    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint liquidity,
        uint baseAmountMin,
        uint deadline
    ) external returns (uint baseAmount, uint quoteAmount);

    function deposit(address baseToken, address quoteToken, address holder, uint amount) external;
    function withdraw(address baseToken, address quoteToken, uint amount) external;

    function openPositionWithWallet(
        address baseToken,
        address quoteToken,
        uint side,
        uint marginAmount,
        uint baseAmount,
        uint quoteAmountLimit,
        uint deadline
    ) external returns (uint quoteAmount);

    function openPositionWithMargin(
        address baseToken,
        address quoteToken,
        uint side,
        uint baseAmount,
        uint quoteAmountLimit,
        uint deadline
    ) external returns (uint quoteAmount);
    
    function closePosition(
        address baseToken,
        address quoteToken,
        uint quoteAmount,
        uint deadline,
        bool autoWithdraw
    ) external returns (uint baseAmount, uint marginAmount);
    
    function getReserves(address baseToken, address quoteToken) external view returns (uint reserveBase, uint reserveQuote);
    function getQuoteAmount(address baseToken, address quoteToken, uint side, uint baseAmount) external view returns (uint quoteAmount);
    function getWithdrawable(address baseToken, address quoteToken, address holder) external view returns (uint amount);
    function getPosition(address baseToken, address quoteToken, address holder) external view returns (int baseSize, int quoteSize, int tradeSize);
}