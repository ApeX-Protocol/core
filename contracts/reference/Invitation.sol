pragma solidity ^0.8.2;

contract Invitation {
    event Invite(address indexed user, address indexed upper, uint256 height);

    struct UserInvitation {
        address upper; //上级
        address[] lowers; //下级
        uint256 startBlock; //邀请块高
    }

    uint256 public startBlock;
    mapping(address => UserInvitation) public userInvitations;
    uint256 public totalRegisterCount = 0;

    constructor() public {
        startBlock = block.number;
    }

    function register() external returns (bool) {
        UserInvitation storage user = userInvitations[msg.sender];
        require(0 == user.startBlock, "REGISTERED");

        user.upper = address(0);
        user.startBlock = block.number;
        totalRegisterCount++;

        emit Invite(msg.sender, user.upper, user.startBlock);

        return true;
    }

    function acceptInvitation(address inviter) external returns (bool) {
        require(msg.sender != inviter, "FORBIDDEN");
        UserInvitation storage sender = userInvitations[msg.sender];

        // ensure not registered
        require(0 == sender.startBlock, "REGISTERED");
        UserInvitation storage upper = userInvitations[inviter];
        // throw exception
        // if (0 == upper.startBlock) {
        //     upper.upper = address(0);
        //     upper.startBlock = block.number;

        //     emit Invite(inviter, upper.upper, upper.startBlock);
        // }
        require(upper.startBlock != 0, "INVITER_NOT_EXIST!");

        sender.upper = inviter;
        upper.lowers.push(msg.sender);
        sender.startBlock = block.number;
        totalRegisterCount++;

        emit Invite(msg.sender, sender.upper, sender.startBlock);

        return true;
    }

    function getUpper1(address user) external view returns (address) {
        return userInvitations[user].upper;
    }

    function getUpper2(address user) external view returns (address, address) {
        address upper1 = userInvitations[user].upper;
        address upper2 = address(0);
        if (address(0) != upper1) {
            upper2 = userInvitations[upper1].upper;
        }

        return (upper1, upper2);
    }

    function getLowers1(address user) external view returns (address[] memory) {
        return userInvitations[user].lowers;
    }

    //todo
    function getLowers2(address user) external view returns (address[] memory, address[] memory) {
        address[] memory lowers1 = userInvitations[user].lowers;
        uint256 count = 0;
        uint256 lowers1Len = lowers1.length;
        // get the  total count;
        for (uint256 i = 0; i < lowers1Len; i++) {
            count += userInvitations[lowers1[i]].lowers.length;
        }
        address[] memory lowers;
        address[] memory lowers2 = new address[](count);
        count = 0;
        for (uint256 i = 0; i < lowers1Len; i++) {
            lowers = userInvitations[lowers1[i]].lowers;
            for (uint256 j = 0; j < lowers.length; j++) {
                lowers2[count] = lowers[j];
                count++;
            }
        }

        return (lowers1, lowers2);
    }

    function getLowers2Count(address user) external view returns (uint256, uint256) {
        address[] memory lowers1 = userInvitations[user].lowers;
        uint256 lowers2Len = 0;
        uint256 len = lowers1.length;
        for (uint256 i = 0; i < len; i++) {
            lowers2Len += userInvitations[lowers1[i]].lowers.length;
        }

        return (lowers1.length, lowers2Len);
    }
}
