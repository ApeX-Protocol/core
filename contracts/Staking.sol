pragma solidity ^0.8.0;

contract Staking is IStaking {
    address public factory;
    address public config;
    address public amm;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    bool private locked = false;
    modifier lock() {
        require(locked == false, "Staking: LOCKED");
        locked = true;
        _;
        locked = false;
    }

    constructor(address _config, address _amm) public {
        factory = msg.sender;
        config = _config;
        amm = _amm;
    }

    function stake(uint256 amount) external lock {
        require(amount > 0, "Staking: Cannot stake 0");
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        IAmm(amm).safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function stakeWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external lock {
        require(amount > 0, "Staking: Cannot stake 0");
        totalSupply += amount;
        balanceOf[msg.sender] += amount;

        // permit
        IUniswapV2ERC20(address(amm)).permit(msg.sender, address(this), amount, deadline, v, r, s);

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }
}
