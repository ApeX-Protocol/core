pragma solidity ^0.8.0;

import './interfaces2/IRouter.sol';
import './interfaces2/IFactory.sol';
import './interfaces2/IAmm.sol';
import './libraries/AmmLibrary.sol';
import './libraries/TransferHelper.sol';

contract Router is IRouter {
    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'Router: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    function addLiquidity(
        address baseToken,
        address quoteToken,
        uint baseAmount,
        uint quoteAmountMin,
        uint deadline,
        bool autoStake
    ) external override ensure(deadline) returns (uint quoteAmount, uint liquidity) {
        if (IFactory(factory).getAmm(baseToken, quoteToken) == address(0)) {
            IFactory(factory).createPair(baseToken, quotoToken);
            IFactory(factory).createStaking(baseToken, quoteToken);
        }
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        TransferHelper.safeTransferFrom(baseToken, msg.sender, amm, baseAmount);
        address to = msg.sender;
        if (autoStake) {
            to = IFactory(factory).getStaking(amm);
        }
        (quoteAmount, liquidity) = IAmm(amm).mint(to);
        require(quoteAmount >= quoteAmountMin, 'Router: INSUFFICIENT_QUOTE_AMOUNT');
    }

    function removeLiquidity(
        address baseToken,
        address quoteToken,
        uint liquidity,
        uint baseAmountMin,
        uint deadline
    ) external override ensure(deadline) returns (uint baseAmount, uint quoteAmount) {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        IAmm(amm).transferFrom(msg.sender, amm, liquidity);
        (baseAmount, quoteAmount) = IAmm(amm).burn(msg.sender);
        require(baseAmount >= baseAmountMin, 'Router: INSUFFICIENT_BASE_AMOUNT');
    }

    function deposit(address baseToken, address quoteToken, address holder, uint amount) external {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        address margin = IFactory(factory).getMargin(amm);
        require(margin != address(0), 'Router: ZERO_ADDRESS');
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, amount);
        IMargin(margin).addMargin(holder, amount);
    }

    function withdraw(address baseToken, address quoteToken, uint amount) external {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        address margin = IFactory(factory).getMargin(amm);
        require(margin != address(0), 'Router: ZERO_ADDRESS');
        IMargin(margin).removeMargin(amount);
    }

    function openPositionWithWallet(
        address baseToken,
        address quoteToken,
        uint side,
        uint marginAmount,
        uint baseAmount,
        uint quoteAmountLimit,
        uint deadline
    ) external returns (uint quoteAmount) {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        address margin = IFactory(factory).getMargin(amm);
        require(margin != address(0), 'Router: ZERO_ADDRESS');
        TransferHelper.safeTransferFrom(baseToken, msg.sender, margin, amount);
        IMargin(margin).addMargin(holder, amount);
    }

    function openPositionWithMargin(
        address baseToken,
        address quoteToken,
        uint side,
        uint baseAmount,
        uint quoteAmountLimit,
        uint deadline
    ) external returns (uint quoteAmount) {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        address margin = IFactory(factory).getMargin(amm);
        require(margin != address(0), 'Router: ZERO_ADDRESS');
        
    }
    
    function closePosition(
        address baseToken,
        address quoteToken,
        uint quoteAmount,
        uint deadline,
        bool autoWithdraw
    ) external returns (uint baseAmount, uint marginAmount) {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        address margin = IFactory(factory).getMargin(amm);
        require(margin != address(0), 'Router: ZERO_ADDRESS');
        
    }
    
    function getReserves(address baseToken, address quoteToken) external view returns (uint reserveBase, uint reserveQuote) {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        (reserveBase, reserveQuote) = IAmm(amm).getReserves(baseToken, quoteToken);
    }

    function getQuoteAmount(address baseToken, address quoteToken, uint side, uint baseAmount) external view returns (uint quoteAmount) {

    }

    function getWithdrawable(address baseToken, address quoteToken, address holder) external view returns (uint amount) {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        address margin = IFactory(factory).getMargin(amm);
        amount = IMargin(margin).getWithdrawable(holder);
    }

    function getPosition(address baseToken, address quoteToken, address holder) external view returns (int baseSize, int quoteSize, int tradeSize) {
        address amm = AmmLibrary.ammFor(factory, baseToken, quoteToken);
        address margin = IFactory(factory).getMargin(amm);
        (baseSize, quoteSize, tradeSize) = IMargin(margin).getPosition(holder);
    }
}