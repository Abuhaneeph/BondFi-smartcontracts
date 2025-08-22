// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Library for core group management functions
library GroupManagement {
    struct SavingsGroup {
        uint256 groupId;
        string name;
        string description;
        address creator;
        string creatorName;
        IERC20 token;
        uint256 contributionAmount;
        uint256 contributionFrequency;
        uint256 maxMembers;
        uint256 currentMembers;
        uint256 currentRound;
        uint256 totalRounds;
        uint256 startTime;
        uint256 lastContributionTime;
        uint256 nextContributionDeadline;
        bool isActive;
        bool isCompleted;
        address[] members;
        string[] memberNames;
        address[] payoutOrder;
        mapping(address => bool) isMember;
        mapping(address => uint256) memberIndex;
        mapping(address => string) memberToName;
        mapping(uint256 => mapping(address => bool)) hasContributed;
        mapping(uint256 => mapping(address => uint256)) contributionTimestamp;
        mapping(uint256 => address) roundRecipient;
        mapping(uint256 => bool) roundCompleted;
        mapping(uint256 => uint256) roundStartTime;
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

    event MemberJoined(uint256 indexed groupId, address indexed member, string memberName);
    event RoundStarted(uint256 indexed groupId, uint256 round, address recipient, string recipientName, uint256 deadline);
    event DefaultDetected(uint256 indexed groupId, address indexed defaulter, string defaulterName, uint256 round);

    function addMember(
        SavingsGroup storage group,
        mapping(address => MemberInfo) storage memberInfo,
        mapping(address => uint256[]) storage userGroups,
        address member,
        string memory memberName
    ) external {
        group.members.push(member);
        group.memberNames.push(memberName);
        group.isMember[member] = true;
        group.memberIndex[member] = group.currentMembers;
        group.memberToName[member] = memberName;
        group.currentMembers++;
        
        userGroups[member].push(group.groupId);
        memberInfo[member].activeGroups++;
        
        emit MemberJoined(group.groupId, member, memberName);
    }

    function startGroup(SavingsGroup storage group) external {
        // Shuffle payout order
        _shuffleArray(group.payoutOrder);
        
        // Set recipients for each round
        for (uint256 i = 0; i < group.totalRounds; i++) {
            group.roundRecipient[i + 1] = group.payoutOrder[i];
        }
        
        group.isActive = true;
        group.currentRound = 1;
        group.startTime = block.timestamp;
        group.lastContributionTime = block.timestamp;
        group.nextContributionDeadline = block.timestamp + group.contributionFrequency + 300; // 5 min grace
        group.roundStartTime[1] = block.timestamp;
        
        emit RoundStarted(group.groupId, 1, 
            group.roundRecipient[1], 
            group.memberToName[group.roundRecipient[1]], 
            group.nextContributionDeadline);
    }

    function handleDefaults(
        SavingsGroup storage group,
        mapping(address => MemberInfo) storage memberInfo,
        mapping(address => string) storage userNames
    ) external {
        for (uint256 i = 0; i < group.members.length; i++) {
            address member = group.members[i];
            if (!group.hasContributed[group.currentRound][member]) {
                memberInfo[member].hasDefaulted = true;
                memberInfo[member].reputationScore = memberInfo[member].reputationScore > 20 ? 
                    memberInfo[member].reputationScore - 20 : 0;
                emit DefaultDetected(group.groupId, member, userNames[member], group.currentRound);
            }
        }
    }

    function _shuffleArray(address[] storage array) internal {
        for (uint256 i = 0; i < array.length; i++) {
            uint256 n = i + uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, i))) % (array.length - i);
            address temp = array[n];
            array[n] = array[i];
            array[i] = temp;
        }
    }
}

// Library for agent management
library AgentManagement {
    struct AjoAgent {
        bool isActive;
        string name;
        string contactInfo;
        uint256 groupsCreated;
        uint256 successfulGroups;
        uint256 failedGroups;
        uint256 reputationScore;
        uint256 registrationDate;
        mapping(string => bool) usedCodes;
        string[] generatedCodes;
    }

    struct InviteCode {
        string code;
        address agent;
        uint256 groupId;
        bool isActive;
        uint256 maxUses;
        uint256 currentUses;
        uint256 expiryTime;
        address[] usedBy;
    }

    event AjoAgentRegistered(address indexed agent, string name, string contactInfo);
    event InviteCodeGenerated(string indexed code, address indexed agent, uint256 indexed groupId, uint256 maxUses);

    function generateUniqueCode(uint256 groupId, address agent) external view returns (string memory) {
        return string(abi.encodePacked(
            "AJO",
            _toString(groupId),
            _toString(uint256(uint160(agent)) % 10000),
            _toString(block.timestamp % 10000)
        ));
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
}

// Library for view functions and data retrieval
library ViewFunctions {
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

    struct ContributionStatus {
        bool hasContributed;
        uint256 contributionTime;
        bool isLate;
        uint256 timeRemaining;
    }

    using GroupManagement for GroupManagement.SavingsGroup;

    function getGroupSummary(
        GroupManagement.SavingsGroup storage group
    ) external view returns (GroupSummary memory) {
        return GroupSummary({
            groupId: group.groupId,
            name: group.name,
            creator: group.creator,
            creatorName: group.creatorName,
            token: address(group.token),
            contributionAmount: group.contributionAmount,
            currentMembers: group.currentMembers,
            maxMembers: group.maxMembers,
            currentRound: group.currentRound,
            totalRounds: group.totalRounds,
            isActive: group.isActive,
            isCompleted: group.isCompleted,
            canJoin: !group.isCompleted && group.currentMembers < group.maxMembers && !group.isActive,
            nextContributionDeadline: group.nextContributionDeadline,
            currentRecipient: group.isActive ? group.roundRecipient[group.currentRound] : address(0),
            currentRecipientName: group.isActive ? group.memberToName[group.roundRecipient[group.currentRound]] : ""
        });
    }

    function getUserContributionStatus(
        GroupManagement.SavingsGroup storage group,
        address user
    ) external view returns (ContributionStatus memory) {
        bool hasContributed = group.hasContributed[group.currentRound][user];
        uint256 contributionTime = group.contributionTimestamp[group.currentRound][user];
        bool isLate = hasContributed && contributionTime > group.roundStartTime[group.currentRound] + group.contributionFrequency;
        uint256 timeRemaining = group.nextContributionDeadline > block.timestamp ? 
            group.nextContributionDeadline - block.timestamp : 0;
        
        return ContributionStatus({
            hasContributed: hasContributed,
            contributionTime: contributionTime,
            isLate: isLate,
            timeRemaining: timeRemaining
        });
    }
}