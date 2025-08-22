// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./SavingLibrary.sol";

/**
 * @title AjoEsusuSavings
 * @dev Minimized contract using libraries to reduce size
 */
contract RotationalSaving is ReentrancyGuard, Ownable, Pausable {
    using GroupManagement for GroupManagement.SavingsGroup;
    using AgentManagement for AgentManagement.AjoAgent;
    using ViewFunctions for GroupManagement.SavingsGroup;
    
    // State variables
    uint256 public nextGroupId = 1;
    uint256 public platformFeePercentage = 50; // 0.5%
    uint256 public constant MIN_CONTRIBUTION_FREQUENCY = 60;
    uint256 public constant GRACE_PERIOD = 300;
    
    mapping(address => uint256) public collectedFees;
    mapping(uint256 => GroupManagement.SavingsGroup) public savingsGroups;
    mapping(address => GroupManagement.MemberInfo) public memberInfo;
    mapping(address => uint256[]) public userGroups;
    mapping(address => uint256[]) public userCompletedGroups;
    mapping(address => bool) public supportedTokens;
    mapping(address => string) public tokenNames;
    mapping(address => string) public userNames;
    address[] public supportedTokensList;
    mapping(address => AgentManagement.AjoAgent) public ajoAgents;
    mapping(string => AgentManagement.InviteCode) public inviteCodes;
    mapping(uint256 => string) public groupInviteCode;
    mapping(address => bool) public isAjoAgent;
    mapping(address => bool) public trustedContracts;
    address[] public allAjoAgents;
    uint256 public agentRegistrationFee = 0;
    uint256 public minAgentReputation = 70;
    
    // Events
    event GroupCreated(uint256 indexed groupId, address indexed creator, string creatorName, string name, address token, uint256 contributionAmount);
    event ContributionMade(uint256 indexed groupId, address indexed member, string memberName, uint256 amount, uint256 round, uint256 timestamp);
    event PayoutDistributed(uint256 indexed groupId, address indexed recipient, string recipientName, uint256 amount, uint256 round);
    event GroupCompleted(uint256 indexed groupId, string name);
    event TokenSupported(address indexed token, string name, bool supported);
    event FeesWithdrawn(address indexed token, uint256 amount, address indexed owner);
    event UserRegistered(address indexed user, string name);
    event AjoAgentDeactivated(address indexed agent, string reason);
    event MemberJoinedWithCode(uint256 indexed groupId, address indexed member, string memberName, string inviteCode, address indexed agent);

    constructor(address[] memory _supportedTokens, string[] memory _tokenNames) Ownable(msg.sender) {
        require(_supportedTokens.length == _tokenNames.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            supportedTokens[_supportedTokens[i]] = true;
            tokenNames[_supportedTokens[i]] = _tokenNames[i];
            supportedTokensList.push(_supportedTokens[i]);
        }
    }

    // Modifiers
    modifier validGroupId(uint256 _groupId) {
        require(_groupId > 0 && _groupId < nextGroupId, "Invalid group ID");
        _;
    }

    modifier onlyGroupMember(uint256 _groupId) {
        require(savingsGroups[_groupId].isMember[msg.sender], "Not a group member");
        _;
    }

    modifier groupActive(uint256 _groupId) {
        require(savingsGroups[_groupId].isActive, "Group not active");
        _;
    }

    modifier registeredUser() {
        require(bytes(userNames[msg.sender]).length > 0, "User not registered");
        _;
    }

    modifier onlyActiveAjoAgent() {
        require(isAjoAgent[msg.sender] && ajoAgents[msg.sender].isActive, "Not an active Ajo agent");
        _;
    }

    modifier validInviteCode(string memory _code) {
        require(bytes(_code).length > 0, "Invalid invite code");
        require(inviteCodes[_code].isActive, "Invite code not active");
        require(inviteCodes[_code].currentUses < inviteCodes[_code].maxUses, "Invite code exhausted");
        require(block.timestamp < inviteCodes[_code].expiryTime, "Invite code expired");
        _;
    }

    // Core functions
    function registerUser(string memory _name) external {
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_name).length <= 50, "Name too long");
        require(!memberInfo[msg.sender].hasRegistered, "Already Registered");
        
        userNames[msg.sender] = _name;
        
        if (memberInfo[msg.sender].joinDate == 0) {
            memberInfo[msg.sender].name = _name;
            memberInfo[msg.sender].reputationScore = 75;
            memberInfo[msg.sender].joinDate = block.timestamp;
            memberInfo[msg.sender].hasRegistered = true;
        }
        memberInfo[msg.sender].lastActivity = block.timestamp;
        
        emit UserRegistered(msg.sender, _name);
    }

    function registerAsAjoAgent(string memory _name, string memory _contactInfo) external payable registeredUser {
        require(!isAjoAgent[msg.sender], "Already an Ajo agent");
        require(msg.value >= agentRegistrationFee, "Insufficient registration fee");
        require(bytes(_name).length > 0 && bytes(_name).length <= 100, "Invalid name");
        require(bytes(_contactInfo).length > 0 && bytes(_contactInfo).length <= 200, "Invalid contact info");
        require(memberInfo[msg.sender].reputationScore >= minAgentReputation, "Insufficient reputation");

        ajoAgents[msg.sender].isActive = true;
        ajoAgents[msg.sender].name = _name;
        ajoAgents[msg.sender].contactInfo = _contactInfo;
        ajoAgents[msg.sender].reputationScore = memberInfo[msg.sender].reputationScore;
        ajoAgents[msg.sender].registrationDate = block.timestamp;

        isAjoAgent[msg.sender] = true;
        allAjoAgents.push(msg.sender);

        emit AgentManagement.AjoAgentRegistered(msg.sender, _name, _contactInfo);
    }

    function createGroup(
        string memory _name,
        string memory _description,
        address _token,
        uint256 _contributionAmount,
        uint256 _contributionFrequency,
        uint256 _maxMembers
    ) external whenNotPaused registeredUser onlyActiveAjoAgent returns (uint256) {
        require(supportedTokens[_token], "Token not supported");
        require(_contributionAmount > 0, "Invalid contribution amount");
        require(_contributionFrequency >= MIN_CONTRIBUTION_FREQUENCY, "Frequency too short");
        require(_maxMembers >= 2 && _maxMembers <= 20, "Invalid max members");
        require(bytes(_name).length > 0 && bytes(_name).length <= 100, "Invalid name");
        require(bytes(_description).length <= 500, "Description too long");
        
        if (isAjoAgent[msg.sender]) {
            ajoAgents[msg.sender].groupsCreated++;
        }

        uint256 groupId = nextGroupId++;
        GroupManagement.SavingsGroup storage group = savingsGroups[groupId];
        
        group.groupId = groupId;
        group.name = _name;
        group.description = _description;
        group.creator = msg.sender;
        group.creatorName = userNames[msg.sender];
        group.token = IERC20(_token);
        group.contributionAmount = _contributionAmount;
        group.contributionFrequency = _contributionFrequency;
        group.maxMembers = _maxMembers;
        group.totalRounds = _maxMembers;
        group.isActive = false;
        
        // Creator automatically joins
        GroupManagement.addMember(group, memberInfo, userGroups, msg.sender, userNames[msg.sender]);
        
        emit GroupCreated(groupId, msg.sender, userNames[msg.sender], _name, _token, _contributionAmount);
        return groupId;
    }

    function joinGroupWithCode(uint256 _groupId, string memory _inviteCode) 
        external 
        validGroupId(_groupId) 
        validInviteCode(_inviteCode) 
        whenNotPaused 
        registeredUser 
    {
        GroupManagement.SavingsGroup storage group = savingsGroups[_groupId];
        AgentManagement.InviteCode storage codeInfo = inviteCodes[_inviteCode];
        
        require(codeInfo.groupId == _groupId, "Code not for this group");
        require(!group.isCompleted, "Group completed");
        require(!group.isMember[msg.sender], "Already a member");
        require(group.currentMembers < group.maxMembers, "Group full");
        require(memberInfo[msg.sender].reputationScore >= 50, "Insufficient reputation");
        
        address agent = codeInfo.agent;
        
        GroupManagement.addMember(group, memberInfo, userGroups, msg.sender, userNames[msg.sender]);
        
        // Update invite code usage
        codeInfo.currentUses++;
        codeInfo.usedBy.push(msg.sender);
        
        emit MemberJoinedWithCode(_groupId, msg.sender, userNames[msg.sender], _inviteCode, agent);
        
        // Start group if full
        if (group.currentMembers == group.maxMembers) {
            GroupManagement.startGroup(group);
        }
    }

    function contribute(uint256 _groupId) external validGroupId(_groupId) onlyGroupMember(_groupId) groupActive(_groupId) nonReentrant {
        GroupManagement.SavingsGroup storage group = savingsGroups[_groupId];
        require(!group.hasContributed[group.currentRound][msg.sender], "Already contributed this round");
        
        bool isFirstRound = group.currentRound == 1;
        bool canContribute = isFirstRound || block.timestamp >= group.lastContributionTime + group.contributionFrequency;
        require(canContribute, "Too early for contribution");

        require(group.token.transferFrom(msg.sender, address(this), group.contributionAmount), "Transfer failed");
        
        group.hasContributed[group.currentRound][msg.sender] = true;
        group.contributionTimestamp[group.currentRound][msg.sender] = block.timestamp;
        memberInfo[msg.sender].totalContributions += group.contributionAmount;
        memberInfo[msg.sender].lastActivity = block.timestamp;
        
        emit ContributionMade(_groupId, msg.sender, userNames[msg.sender], group.contributionAmount, group.currentRound, block.timestamp);
        
        _checkRoundCompletion(_groupId);
    }

    function claimPayout(uint256 _groupId) external validGroupId(_groupId) onlyGroupMember(_groupId) nonReentrant {
        GroupManagement.SavingsGroup storage group = savingsGroups[_groupId];
        require(group.roundRecipient[group.currentRound] == msg.sender, "Not your turn");
        require(!group.roundCompleted[group.currentRound], "Already claimed");
        require(_isRoundReadyForPayout(_groupId), "Round not ready for payout");

        uint256 totalAmount = group.contributionAmount * group.currentMembers;
        uint256 platformFee = (totalAmount * platformFeePercentage) / 10000;
        uint256 payoutAmount = totalAmount - platformFee;

        group.roundCompleted[group.currentRound] = true;
        memberInfo[msg.sender].totalReceived += payoutAmount;
        memberInfo[msg.sender].lastActivity = block.timestamp;

        require(group.token.transfer(msg.sender, payoutAmount), "Payout failed");
        
        if (platformFee > 0) {
            collectedFees[address(group.token)] += platformFee;
        }

        emit PayoutDistributed(_groupId, msg.sender, userNames[msg.sender], payoutAmount, group.currentRound);

        if (group.currentRound < group.totalRounds) {
            group.currentRound++;
            group.lastContributionTime = block.timestamp;
            group.nextContributionDeadline = block.timestamp + group.contributionFrequency + GRACE_PERIOD;
            group.roundStartTime[group.currentRound] = block.timestamp;
        } else {
            _completeGroup(_groupId);
        }
    }

    function generateInviteCode(
        uint256 _groupId, 
        uint256 _maxUses, 
        uint256 _validityDays
    ) external validGroupId(_groupId) onlyActiveAjoAgent returns (string memory) {
        require(savingsGroups[_groupId].creator == msg.sender, "Not the group creator");
        require(!savingsGroups[_groupId].isActive, "Group already active");
        require(_maxUses > 0 && _maxUses <= 50, "Invalid max uses");
        require(_validityDays > 0 && _validityDays <= 30, "Invalid validity period");

        string memory code = AgentManagement.generateUniqueCode(_groupId, msg.sender);
        
        inviteCodes[code] = AgentManagement.InviteCode({
            code: code,
            agent: msg.sender,
            groupId: _groupId,
            isActive: true,
            maxUses: _maxUses,
            currentUses: 0,
            expiryTime: block.timestamp + (_validityDays * 1 days),
            usedBy: new address[](0)
        });

        groupInviteCode[_groupId] = code;
        ajoAgents[msg.sender].usedCodes[code] = true;
        ajoAgents[msg.sender].generatedCodes.push(code);

        emit AgentManagement.InviteCodeGenerated(code, msg.sender, _groupId, _maxUses);
        return code;
    }

    // View functions
    function getGroupSummary(uint256 _groupId) external view validGroupId(_groupId) returns (ViewFunctions.GroupSummary memory) {
        return ViewFunctions.getGroupSummary(savingsGroups[_groupId]);
    }

    function getUserContributionStatus(uint256 _groupId, address _user) external view validGroupId(_groupId) returns (ViewFunctions.ContributionStatus memory) {
        return ViewFunctions.getUserContributionStatus(savingsGroups[_groupId], _user);
    }

    function getSupportedTokens() external view returns (address[] memory addresses, string[] memory names) {
        string[] memory tokenNamesList = new string[](supportedTokensList.length);
        for (uint256 i = 0; i < supportedTokensList.length; i++) {
            tokenNamesList[i] = tokenNames[supportedTokensList[i]];
        }
        return (supportedTokensList, tokenNamesList);
    }

    function getUserName(address _user) external view returns (string memory) {
        return userNames[_user];
    }

    function getMemberInfo(address _member) external view returns (GroupManagement.MemberInfo memory) {
        return memberInfo[_member];
    }

    // Internal functions
    function _checkRoundCompletion(uint256 _groupId) internal {
        GroupManagement.SavingsGroup storage group = savingsGroups[_groupId];
        
        uint256 contributorCount = 0;
        for (uint256 i = 0; i < group.members.length; i++) {
            if (group.hasContributed[group.currentRound][group.members[i]]) {
                contributorCount++;
            }
        }
        
        if (contributorCount < group.currentMembers && 
            block.timestamp > group.nextContributionDeadline) {
            GroupManagement.handleDefaults(group, memberInfo, userNames);
        }
    }

    function _isRoundReadyForPayout(uint256 _groupId) internal view returns (bool) {
        GroupManagement.SavingsGroup storage group = savingsGroups[_groupId];
        
        uint256 contributorCount = 0;
        for (uint256 i = 0; i < group.members.length; i++) {
            if (group.hasContributed[group.currentRound][group.members[i]]) {
                contributorCount++;
            }
        }
        
        return contributorCount == group.currentMembers;
    }

    function _completeGroup(uint256 _groupId) internal {
        GroupManagement.SavingsGroup storage group = savingsGroups[_groupId];
        
        group.isActive = false;
        group.isCompleted = true;
        
        for (uint256 i = 0; i < group.members.length; i++) {
            address member = group.members[i];
            memberInfo[member].activeGroups--;
            memberInfo[member].completedGroups++;
            
            userCompletedGroups[member].push(_groupId);
            
            if (!memberInfo[member].hasDefaulted) {
                memberInfo[member].reputationScore = memberInfo[member].reputationScore < 90 ? 
                    memberInfo[member].reputationScore + 10 : 100;
            }
        }

        address creator = group.creator;
        if (isAjoAgent[creator]) {
            bool groupSuccessful = true;
            
            for (uint256 i = 0; i < group.members.length; i++) {
                if (memberInfo[group.members[i]].hasDefaulted) {
                    groupSuccessful = false;
                    break;
                }
            }
            
            if (groupSuccessful) {
                ajoAgents[creator].successfulGroups++;
                if (ajoAgents[creator].reputationScore < 95) {
                    ajoAgents[creator].reputationScore += 5;
                }
            } else {
                ajoAgents[creator].failedGroups++;
                if (ajoAgents[creator].reputationScore > 10) {
                    ajoAgents[creator].reputationScore -= 10;
                }
                
                if (ajoAgents[creator].reputationScore < 30) {
                    ajoAgents[creator].isActive = false;
                    emit AjoAgentDeactivated(creator, "Low reputation due to failed groups");
                }
            }
        }
        
        emit GroupCompleted(_groupId, group.name);
    }

    // Admin functions
    function addSupportedToken(address _token, string memory _name) external onlyOwner {
        require(!supportedTokens[_token], "Token already supported");
        supportedTokens[_token] = true;
        tokenNames[_token] = _name;
        supportedTokensList.push(_token);
        emit TokenSupported(_token, _name, true);
    }

    function setPlatformFee(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 1000, "Fee too high");
        platformFeePercentage = _feePercentage;
    }

    function withdrawFees(address _token, uint256 _amount) external onlyOwner {
        require(_amount <= collectedFees[_token], "Insufficient fees collected");
        collectedFees[_token] -= _amount;
        require(IERC20(_token).transfer(owner(), _amount), "Withdrawal failed");
        emit FeesWithdrawn(_token, _amount, owner());
    }

    function addTrustedContract(address _contract) external onlyOwner {
        require(_contract != address(0), "Invalid contract address");
        trustedContracts[_contract] = true;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}