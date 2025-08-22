// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ISavings Interface
 * @dev Updated interface for AjoEsusuSavings contract with trusted contract functions
 */
interface IAjoEsusuSavings {
    
    // Structs
    struct GroupSummary {
        uint256 groupId;
        string name;
        address creator;
        string creatorName;
        address token;
        uint256 contributionAmount;
        uint256 currentMembers;
        uint256 maxMembers;
        uint256 currentRound;
        uint256 totalRounds;
        bool isActive;
        bool isCompleted;
        bool canJoin;
        uint256 nextContributionDeadline;
        address currentRecipient;
        string currentRecipientName;
    }

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

    struct ContributionStatus {
        bool hasContributed;
        uint256 contributionTime;
        bool isLate;
        uint256 timeRemaining;
    }

    // Events
    event GroupCreated(uint256 indexed groupId, address indexed creator, string creatorName, string name, address token, uint256 contributionAmount);
    event MemberJoined(uint256 indexed groupId, address indexed member, string memberName);
    event ContributionMade(uint256 indexed groupId, address indexed member, string memberName, uint256 amount, uint256 round, uint256 timestamp);
    event PayoutDistributed(uint256 indexed groupId, address indexed recipient, string recipientName, uint256 amount, uint256 round);
    event GroupCompleted(uint256 indexed groupId, string name);
    event DefaultDetected(uint256 indexed groupId, address indexed defaulter, string defaulterName, uint256 round);
    event TokenSupported(address indexed token, string name, bool supported);
    event FeesWithdrawn(address indexed token, uint256 amount, address indexed owner);
    event UserRegistered(address indexed user, string name);
    event RoundStarted(uint256 indexed groupId, uint256 round, address recipient, string recipientName, uint256 deadline);
    event AjoAgentRegistered(address indexed agent, string name, string contactInfo);
    event AjoAgentDeactivated(address indexed agent, string reason);
    event InviteCodeGenerated(string indexed code, address indexed agent, uint256 indexed groupId, uint256 maxUses);
    event MemberJoinedWithCode(uint256 indexed groupId, address indexed member, string memberName, string inviteCode, address indexed agent);

    // User Management
    function registerUser(string memory _name) external;
    function registerAsAjoAgent(string memory _name, string memory _contactInfo) external payable;
    function getUserName(address _user) external view returns (string memory);
    function isUserRegistered(address _user) external view returns (bool);
    function getMemberInfo(address _member) external view returns (MemberInfo memory);

    // Group Management - Original Functions
    function createGroup(
        string memory _name,
        string memory _description,
        address _token,
        uint256 _contributionAmount,
        uint256 _contributionFrequency,
        uint256 _maxMembers
    ) external returns (uint256);

    function joinGroupWithCode(uint256 _groupId, string memory _inviteCode) external;
    function contribute(uint256 _groupId) external;
    function claimPayout(uint256 _groupId) external;

    // Trusted Contract Management
    function addTrustedContract(address _contract) external;
    function removeTrustedContract(address _contract) external;
    function isTrustedContract(address _contract) external view returns (bool);

    // Group Management - OnBehalf Functions (for trusted contracts)
    function createGroupOnBehalf(
        address _creator,
        string memory _name,
        string memory _description,
        address _token,
        uint256 _contributionAmount,
        uint256 _contributionFrequency,
        uint256 _maxMembers
    ) external returns (uint256);

    function joinGroupWithCodeOnBehalf(
        address _member, 
        uint256 _groupId, 
        string memory _inviteCode
    ) external;

    function contributeOnBehalf(
        address _member,
        uint256 _groupId,
        uint256 _amount
    ) external;

    function claimPayoutOnBehalf(
        address _member,
        uint256 _groupId
    ) external returns (uint256);

    // Invite Code Management
    function generateInviteCode(
        uint256 _groupId, 
        uint256 _maxUses, 
        uint256 _validityDays
    ) external returns (string memory);

    function deactivateInviteCode(string memory _code) external;

    function getInviteCodeInfo(string memory _code) external view returns (
        address agent,
        string memory agentName,
        uint256 groupId,
        string memory groupName,
        bool isActive,
        uint256 maxUses,
        uint256 currentUses,
        uint256 expiryTime
    );

    // View Functions - Group Information
    function getGroupSummary(uint256 _groupId) external view returns (GroupSummary memory);
    
    function getGroupDetails(uint256 _groupId) external view returns (
        string memory name,
        string memory description,
        address creator,
        string memory creatorName,
        address token,
        string memory tokenName,
        uint256 contributionAmount,
        uint256 contributionFrequency,
        uint256 currentMembers,
        uint256 maxMembers,
        uint256 currentRound,
        uint256 totalRounds,
        bool isActive,
        bool isCompleted,
        uint256 startTime,
        uint256 nextContributionDeadline
    );

    function getGroupMembersWithNames(uint256 _groupId) external view returns (
        address[] memory addresses, 
        string[] memory names
    );

    function getPayoutOrder(uint256 _groupId) external view returns (
        address[] memory addresses, 
        string[] memory names
    );

    function getUserContributionStatus(uint256 _groupId, address _user) external view returns (ContributionStatus memory);
    
    function getCurrentRecipient(uint256 _groupId) external view returns (
        address recipient, 
        string memory name
    );

    // View Functions - Lists and Collections
    function getAllActiveGroups() external view returns (GroupSummary[] memory);
    function getJoinableGroups() external view returns (GroupSummary[] memory);
    function getUserGroups(address _user) external view returns (uint256[] memory);
    function getUserCompletedGroups(address _user) external view returns (uint256[] memory);

    // Token Management
    function addSupportedToken(address _token, string memory _name) external;
    function removeSupportedToken(address _token) external;
    function getSupportedTokens() external view returns (
        address[] memory addresses, 
        string[] memory names
    );

    // Agent Management
    function getAjoAgentInfo(address _agent) external view returns (
        bool isActive,
        string memory name,
        string memory contactInfo,
        uint256 groupsCreated,
        uint256 successfulGroups,
        uint256 failedGroups,
        uint256 reputationScore,
        uint256 registrationDate
    );

    function getAllActiveAgents() external view returns (address[] memory);
    function setAgentRegistrationFee(uint256 _fee) external;
    function setMinAgentReputation(uint256 _minReputation) external;
    function deactivateAgent(address _agent, string memory _reason) external;

    // Platform Management
    function setPlatformFee(uint256 _feePercentage) external;
    function withdrawFees(address _token, uint256 _amount) external;
    function withdrawAllFees(address _token) external;
    function getAccumulatedFees(address _token) external view returns (uint256);

    // Statistics
    function getTotalStats() external view returns (
        uint256 totalGroups,
        uint256 activeGroups,
        uint256 completedGroups,
        uint256 totalUsers
    );

    // State Variables Access
    function nextGroupId() external view returns (uint256);
    function platformFeePercentage() external view returns (uint256);
    function supportedTokens(address _token) external view returns (bool);
    function tokenNames(address _token) external view returns (string memory);
    function userNames(address _user) external view returns (string memory);
    function isAjoAgent(address _agent) external view returns (bool);
    function trustedContracts(address _contract) external view returns (bool);

    // Emergency Functions
    function pause() external;
    function unpause() external;
    function emergencyWithdraw(uint256 _groupId, address _token) external;
}