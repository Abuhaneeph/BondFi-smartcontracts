// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAjoEsusuSavings {
    struct MemberInfo {
        string name;
        uint256 totalContributions;
        uint256 totalReceived;
        uint256 activeGroups;
        uint256 completedGroups;
        bool hasRegistered;
        bool hasDefaulted;
        uint256 reputationScore;
        uint256 joinDate;
        uint256 lastActivity;
    }
        
    function getMemberInfo(address _member) external view returns (MemberInfo memory);
    function getUserName(address _user) external view returns (string memory);
    function isUserRegistered(address _user) external view returns (bool);
    function supportedTokens(address _token) external view returns (bool);
    function tokenNames(address _token) external view returns (string memory);
}
