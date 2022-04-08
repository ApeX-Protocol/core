// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../core/interfaces/IERC20.sol";
import "../utils/Whitelist.sol";

contract EsAPEX is IERC20, Whitelist {
    string public constant override name = "esApeX Token";
    string public constant override symbol = "esApeX";
    uint8 public constant override decimals = 18;

    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    constructor(address _stakingPoolFactory) {
        owner = msg.sender;
        _addOperator(_stakingPoolFactory);
    }

    function mint(address to, uint256 value) external onlyOperator returns (bool) {
        _mint(to, value);
        return true;
    }

    function burn(address from, uint256 value) external onlyOperator returns (bool) {
        _burn(from, value);
        return true;
    }

    function transfer(address to, uint256 value) external override operatorOrWhitelist returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override operatorOrWhitelist returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= value, "ERC20: transfer amount exceeds allowance");
            allowance[from][msg.sender] = currentAllowance - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply + value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        balanceOf[from] = balanceOf[from] - value;
        totalSupply = totalSupply - value;
        emit Transfer(from, address(0), value);
    }

    function _approve(
        address _owner,
        address spender,
        uint256 value
    ) private {
        allowance[_owner][spender] = value;
        emit Approval(_owner, spender, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) private {
        uint256 fromBalance = balanceOf[from];
        require(fromBalance >= value, "ERC20: transfer amount exceeds balance");
        balanceOf[from] = fromBalance - value;
        balanceOf[to] = balanceOf[to] + value;
        emit Transfer(from, to, value);
    }
}
