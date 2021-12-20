//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20FlashMint.sol";
import "../core/interfaces/IMargin.sol";

interface IERC20Mint {
    function mint(address spender, uint256 amount) external;
}

contract MockFlashAttacker is IERC3156FlashBorrower {
    ERC20FlashMint public baseToken;
    IMargin public margin;
    address public quoteToken;

    enum Action {
        action1,
        action2
    }

    struct FlashData {
        uint256 baseAmount;
        Action action;
    }

    constructor(
        address _token,
        address _margin,
        address _quoteToken
    ) {
        baseToken = ERC20FlashMint(_token);
        margin = IMargin(_margin);
        quoteToken = _quoteToken;
    }

    function onFlashLoan(
        address _initiator,
        address _token,
        uint256 _amount,
        uint256 _fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(_initiator == address(this), "");
        uint8 long = 0;
        FlashData memory flashData = abi.decode(data, (FlashData));
        if (flashData.action == Action.action1) {
            IERC20(_token).transfer(address(margin), flashData.baseAmount);
            margin.addMargin(address(this), flashData.baseAmount);
            margin.openPosition(address(this), long, flashData.baseAmount * 2);
            margin.closePosition(address(this), flashData.baseAmount * 2);
        } else {
            IERC20(_token).transfer(address(margin), flashData.baseAmount);
            margin.addMargin(address(this), flashData.baseAmount);
            margin.openPosition(address(this), long, flashData.baseAmount * 2);
            margin.removeMargin(address(this), address(this), 1);
        }

        IERC20(_token).approve(address(_token), _amount + _fee);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function attack1(uint256 borrow, uint256 baseAmount) public {
        baseToken.flashLoan(
            IERC3156FlashBorrower(this),
            address(baseToken),
            borrow,
            abi.encode(FlashData(baseAmount, Action.action1))
        );
    }

    function attack2(uint256 borrow, uint256 baseAmount) public {
        IERC20Mint(address(baseToken)).mint(address(this), 1000);
        baseToken.flashLoan(
            IERC3156FlashBorrower(this),
            address(baseToken),
            borrow,
            abi.encode(FlashData(baseAmount, Action.action2))
        );
    }
}
