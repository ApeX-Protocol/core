import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";

contract TestWETH {
    address public WETH;
    constructor(address weth) {
        WETH = weth;
    }

    function depositETH() external payable {
        
    }

    function getWethBalance() external view returns (uint256) {
        return IERC20(WETH).balanceOf(address(this));
    }

    function withdrawWETH() external {
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        IWETH(WETH).withdraw(wethBalance);
    }
}