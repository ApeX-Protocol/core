pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ApeXToken is ERC20Votes, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _minters;
    uint256 private constant preMineSupply = 1_000_000_000e18; // 1 billion

    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "ApeXToken: caller is not the minter");
        _;
    }

    constructor() ERC20Permit("") ERC20("ApeXToken", "APEX") {
        _mint(msg.sender, preMineSupply);
    }

    function mint(address to_, uint256 amount_) external onlyMinter returns (bool) {
        _mint(to_, amount_);
        return true;
    }

    function addMinter(address minter) external onlyOwner returns (bool) {
        require(minter != address(0), "ApeXToken.addMinter: is the zero address");
        return EnumerableSet.add(_minters, minter);
    }

    function delMinter(address minter) external onlyOwner returns (bool) {
        require(minter != address(0), "BXHToken.delMinter is the zero address");
        return EnumerableSet.remove(_minters, minter);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(_minters, account);
    }

    function getMinterLength() external view returns (uint256) {
        return EnumerableSet.length(_minters);
    }

    function getMinter(uint256 index) external view onlyOwner returns (address) {
        require(index <= EnumerableSet.length(_minters) - 1, "ApeXToken.getMinter: index out of bounds");
        return EnumerableSet.at(_minters, index);
    }
}
