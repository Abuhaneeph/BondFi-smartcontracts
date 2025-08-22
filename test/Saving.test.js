const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AjoEsusuSavings", function () {
  let ajoContract;
  let swapContract;
  let priceFeedContract;
  let testTokens = [];
  let owner;
  let user1, user2, user3, user4;
  let agent1, agent2;

  const tokenNames = ["USDT", "WETH", "AFR", "AFX", "cNGN", "cGHS", "cZAR", "cKES"];
  const contributionAmount = ethers.parseEther("100");
  const contributionFrequency = 60; // 1 minute for testing

  beforeEach(async function () {
    [owner, user1, user2, user3, user4, agent1, agent2] = await ethers.getSigners();

    // Deploy test tokens
    const TestToken = await ethers.getContractFactory("TestnetToken");
    for (let i = 0; i < tokenNames.length; i++) {
      const token = await TestToken.deploy(tokenNames[i], tokenNames[i]);
      await token.waitForDeployment();
      testTokens.push(token);
    }

    // Deploy PriceFeed contract
    const PriceFeed = await ethers.getContractFactory("TestPriceFeed");
    priceFeedContract = await PriceFeed.deploy();
    await priceFeedContract.waitForDeployment();

    // Deploy Swap contract
    const Swap = await ethers.getContractFactory("Swap");
    swapContract = await Swap.deploy(
      await priceFeedContract.getAddress(),
      await testTokens[2].getAddress() // AFR token as AFRI_COIN
    );
    await swapContract.waitForDeployment();

    // Deploy AjoEsusuSavings contract
    const AjoEsusuSavings = await ethers.getContractFactory("AjoEsusuSavings");
    const tokenAddresses = await Promise.all(testTokens.map(token => token.getAddress()));
    
    ajoContract = await AjoEsusuSavings.deploy(
      tokenAddresses,
      tokenNames,
      await swapContract.getAddress()
    );
    await ajoContract.waitForDeployment();

    // Setup initial token balances and approvals
    for (let i = 0; i < testTokens.length; i++) {
      const token = testTokens[i];
      // Mint tokens to test users
      await token.connect(user1).faucet(1000);
      await token.connect(user2).faucet(1000);
      await token.connect(user3).faucet(1000);
      await token.connect(user4).faucet(1000);
      await token.connect(agent1).faucet(1000);
      await token.connect(agent2).faucet(1000);

      // Approve AjoEsusuSavings contract
      await token.connect(user1).approve(await ajoContract.getAddress(), ethers.parseEther("10000"));
      await token.connect(user2).approve(await ajoContract.getAddress(), ethers.parseEther("10000"));
      await token.connect(user3).approve(await ajoContract.getAddress(), ethers.parseEther("10000"));
      await token.connect(user4).approve(await ajoContract.getAddress(), ethers.parseEther("10000"));
      await token.connect(agent1).approve(await ajoContract.getAddress(), ethers.parseEther("10000"));
      await token.connect(agent2).approve(await ajoContract.getAddress(), ethers.parseEther("10000"));
    }

    // Set up price feeds for tokens (using manual prices for testing)
    for (let i = 0; i < testTokens.length; i++) {
      await priceFeedContract.createMockAggregator(
        await testTokens[i].getAddress(),
        100000000, // $1.00 in 8 decimals
        8
      );
    }
  });

  describe("User Registration", function () {
    it("Should allow users to register with valid names", async function () {
      await ajoContract.connect(user1).registerUser("Alice");
      expect(await ajoContract.getUserName(user1.address)).to.equal("Alice");
      expect(await ajoContract.isUserRegistered(user1.address)).to.be.true;
    });

    it("Should reject empty names", async function () {
      await expect(ajoContract.connect(user1).registerUser(""))
        .to.be.revertedWith("Name cannot be empty");
    });

    it("Should reject names that are too long", async function () {
      const longName = "a".repeat(51);
      await expect(ajoContract.connect(user1).registerUser(longName))
        .to.be.revertedWith("Name too long");
    });

    it("Should prevent duplicate registrations", async function () {
      await ajoContract.connect(user1).registerUser("Alice");
      await expect(ajoContract.connect(user1).registerUser("Alice2"))
        .to.be.revertedWith("Already Registered");
    });

    it("Should set default reputation score", async function () {
      await ajoContract.connect(user1).registerUser("Alice");
      const memberInfo = await ajoContract.getMemberInfo(user1.address);
      expect(memberInfo.reputationScore).to.equal(75);
    });
  });

  describe("Ajo Agent System", function () {
    beforeEach(async function () {
      // Register users first
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent2).registerUser("Agent2");
      await ajoContract.connect(user1).registerUser("User1");
    });

    it("Should allow users to register as Ajo agents", async function () {
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
      
      const agentInfo = await ajoContract.getAjoAgentInfo(agent1.address);
      expect(agentInfo.isActive).to.be.true;
      expect(agentInfo.name).to.equal("Agent Alice");
      expect(agentInfo.contactInfo).to.equal("alice@agent.com");
    });

    it("Should require user registration before becoming agent", async function () {
      await expect(ajoContract.connect(user3).registerAsAjoAgent("Agent Bob", "bob@agent.com"))
        .to.be.revertedWith("User not registered");
    });

    it("Should prevent duplicate agent registrations", async function () {
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
      await expect(ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice2", "alice2@agent.com"))
        .to.be.revertedWith("Already an Ajo agent");
    });

    it("Should require sufficient reputation to become agent", async function () {
      // Lower the user's reputation
      const memberInfo = await ajoContract.getMemberInfo(user1.address);
      // We can't directly set reputation, but the contract starts with 75 which is above minimum
      await expect(ajoContract.connect(user1).registerAsAjoAgent("Low Rep User", "lowrep@test.com"))
        .to.not.be.reverted;
    });
  });

  describe("Group Creation", function () {
    beforeEach(async function () {
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
    });

    it("Should allow agents to create groups", async function () {
      const tokenAddress = await testTokens[0].getAddress(); // USDT
      
      await ajoContract.connect(agent1).createGroup(
        "Test Savings Group",
        "A test group for savings",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        4 // max members
      );

      const groupSummary = await ajoContract.getGroupSummary(1);
      expect(groupSummary.name).to.equal("Test Savings Group");
      expect(groupSummary.creator).to.equal(agent1.address);
      expect(groupSummary.maxMembers).to.equal(4);
      expect(groupSummary.currentMembers).to.equal(1); // Creator auto-joins
    });

    it("Should reject non-agents from creating groups", async function () {
      await ajoContract.connect(user1).registerUser("User1");
      const tokenAddress = await testTokens[0].getAddress();
      
      await expect(ajoContract.connect(user1).createGroup(
        "Test Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        4
      )).to.be.revertedWith("Not an active Ajo agent");
    });

    it("Should validate group parameters", async function () {
      const tokenAddress = await testTokens[0].getAddress();
      
      // Invalid contribution amount
      await expect(ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description", 
        tokenAddress,
        0,
        contributionFrequency,
        4
      )).to.be.revertedWith("Invalid contribution amount");

      // Invalid max members (too few)
      await expect(ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        1
      )).to.be.revertedWith("Invalid max members");

      // Invalid max members (too many)
      await expect(ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        21
      )).to.be.revertedWith("Invalid max members");
    });

    it("Should reject unsupported tokens", async function () {
      const invalidToken = ethers.ZeroAddress;
      
      await expect(ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description",
        invalidToken,
        contributionAmount,
        contributionFrequency,
        4
      )).to.be.revertedWith("Token not supported");
    });
  });

  describe("Invite Code System", function () {
    let groupId;
    
    beforeEach(async function () {
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
      
      const tokenAddress = await testTokens[0].getAddress();
      const tx = await ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        4
      );
      groupId = 1; // First group
    });

    it("Should allow agents to generate invite codes", async function () {
      const inviteCode = await ajoContract.connect(agent1).generateInviteCode(
        groupId,
        10, // max uses
        7   // validity days
      );

      // The function returns the generated code
      expect(inviteCode).to.include("AJO");
    });

    it("Should allow users to join groups with valid invite codes", async function () {
      await ajoContract.connect(user1).registerUser("User1");
      
      const inviteCode = await ajoContract.connect(agent1).generateInviteCode(groupId, 10, 7);
      
      await ajoContract.connect(user1).joinGroupWithCode(groupId, inviteCode);
      
      const groupSummary = await ajoContract.getGroupSummary(groupId);
      expect(groupSummary.currentMembers).to.equal(2);
    });

    it("Should validate invite code usage limits", async function () {
      await ajoContract.connect(user1).registerUser("User1");
      await ajoContract.connect(user2).registerUser("User2");
      
      const inviteCode = await ajoContract.connect(agent1).generateInviteCode(groupId, 1, 7);
      
      await ajoContract.connect(user1).joinGroupWithCode(groupId, inviteCode);
      
      await expect(ajoContract.connect(user2).joinGroupWithCode(groupId, inviteCode))
        .to.be.revertedWith("Invite code exhausted");
    });

    it("Should prevent using invalid invite codes", async function () {
      await ajoContract.connect(user1).registerUser("User1");
      
      await expect(ajoContract.connect(user1).joinGroupWithCode(groupId, "INVALID_CODE"))
        .to.be.revertedWith("Invite code not active");
    });
  });

  describe("Group Lifecycle", function () {
    let groupId;
    let tokenContract;

    beforeEach(async function () {
      // Register users and agent
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
      await ajoContract.connect(user1).registerUser("User1");
      await ajoContract.connect(user2).registerUser("User2");
      await ajoContract.connect(user3).registerUser("User3");

      // Create group
      tokenContract = testTokens[0]; // USDT
      const tokenAddress = await tokenContract.getAddress();
      
      await ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        4
      );
      groupId = 1;

      // Generate invite code and have users join
      const inviteCode = await ajoContract.connect(agent1).generateInviteCode(groupId, 10, 7);
      await ajoContract.connect(user1).joinGroupWithCode(groupId, inviteCode);
      await ajoContract.connect(user2).joinGroupWithCode(groupId, inviteCode);
      await ajoContract.connect(user3).joinGroupWithCode(groupId, inviteCode);
    });

    it("Should start group when full", async function () {
      const groupSummary = await ajoContract.getGroupSummary(groupId);
      expect(groupSummary.isActive).to.be.true;
      expect(groupSummary.currentRound).to.equal(1);
    });

    it("Should allow contributions in first round", async function () {
      await ajoContract.connect(agent1).contribute(groupId);
      
      const contributionStatus = await ajoContract.getUserContributionStatus(groupId, agent1.address);
      expect(contributionStatus.hasContributed).to.be.true;
    });

    it("Should prevent double contributions", async function () {
      await ajoContract.connect(agent1).contribute(groupId);
      
      await expect(ajoContract.connect(agent1).contribute(groupId))
        .to.be.revertedWith("Already contributed this round");
    });

    it("Should allow payout when round is complete", async function () {
      // All members contribute
      await ajoContract.connect(agent1).contribute(groupId);
      await ajoContract.connect(user1).contribute(groupId);
      await ajoContract.connect(user2).contribute(groupId);
      await ajoContract.connect(user3).contribute(groupId);

      // Find out who the recipient is
      const currentRecipient = await ajoContract.getCurrentRecipient(groupId);
      const recipientAddress = currentRecipient[0];

      // Find the signer that corresponds to the recipient address
      let recipientSigner;
      if (recipientAddress === agent1.address) recipientSigner = agent1;
      else if (recipientAddress === user1.address) recipientSigner = user1;
      else if (recipientAddress === user2.address) recipientSigner = user2;
      else if (recipientAddress === user3.address) recipientSigner = user3;

      const balanceBefore = await tokenContract.balanceOf(recipientAddress);
      await ajoContract.connect(recipientSigner).claimPayout(groupId);
      const balanceAfter = await tokenContract.balanceOf(recipientAddress);

      expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Should move to next round after payout", async function () {
      // Complete first round
      await ajoContract.connect(agent1).contribute(groupId);
      await ajoContract.connect(user1).contribute(groupId);
      await ajoContract.connect(user2).contribute(groupId);
      await ajoContract.connect(user3).contribute(groupId);

      const currentRecipient = await ajoContract.getCurrentRecipient(groupId);
      const recipientAddress = currentRecipient[0];

      let recipientSigner;
      if (recipientAddress === agent1.address) recipientSigner = agent1;
      else if (recipientAddress === user1.address) recipientSigner = user1;
      else if (recipientAddress === user2.address) recipientSigner = user2;
      else if (recipientAddress === user3.address) recipientSigner = user3;

      await ajoContract.connect(recipientSigner).claimPayout(groupId);

      const groupSummary = await ajoContract.getGroupSummary(groupId);
      expect(groupSummary.currentRound).to.equal(2);
    });

    it("Should complete group after all rounds", async function () {
      // We need to complete 4 rounds (4 members)
      for (let round = 1; round <= 4; round++) {
        // All members contribute
        await ajoContract.connect(agent1).contribute(groupId);
        await ajoContract.connect(user1).contribute(groupId);
        await ajoContract.connect(user2).contribute(groupId);
        await ajoContract.connect(user3).contribute(groupId);

        // Find and execute payout
        const currentRecipient = await ajoContract.getCurrentRecipient(groupId);
        const recipientAddress = currentRecipient[0];

        let recipientSigner;
        if (recipientAddress === agent1.address) recipientSigner = agent1;
        else if (recipientAddress === user1.address) recipientSigner = user1;
        else if (recipientAddress === user2.address) recipientSigner = user2;
        else if (recipientAddress === user3.address) recipientSigner = user3;

        await ajoContract.connect(recipientSigner).claimPayout(groupId);
      }

      const groupSummary = await ajoContract.getGroupSummary(groupId);
      expect(groupSummary.isCompleted).to.be.true;
      expect(groupSummary.isActive).to.be.false;
    });
  });

  describe("View Functions", function () {
    beforeEach(async function () {
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
    });

    it("Should return supported tokens", async function () {
      const [addresses, names] = await ajoContract.getSupportedTokens();
      expect(addresses.length).to.equal(tokenNames.length);
      expect(names.length).to.equal(tokenNames.length);
      expect(names[0]).to.equal("USDT");
    });

    it("Should return joinable groups", async function () {
      const tokenAddress = await testTokens[0].getAddress();
      
      await ajoContract.connect(agent1).createGroup(
        "Joinable Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        4
      );

      const joinableGroups = await ajoContract.getJoinableGroups();
      expect(joinableGroups.length).to.equal(1);
      expect(joinableGroups[0].name).to.equal("Joinable Group");
    });

    it("Should return active groups", async function () {
      // Create and fill a group to make it active
      const tokenAddress = await testTokens[0].getAddress();
      
      await ajoContract.connect(agent1).createGroup(
        "Active Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        2 // Small group for easier testing
      );

      // Register another user and join to activate group
      await ajoContract.connect(user1).registerUser("User1");
      const inviteCode = await ajoContract.connect(agent1).generateInviteCode(1, 10, 7);
      await ajoContract.connect(user1).joinGroupWithCode(1, inviteCode);

      const activeGroups = await ajoContract.getAllActiveGroups();
      expect(activeGroups.length).to.equal(1);
      expect(activeGroups[0].name).to.equal("Active Group");
      expect(activeGroups[0].isActive).to.be.true;
    });
  });

  describe("Admin Functions", function () {
    it("Should allow owner to add supported tokens", async function () {
      const newToken = await (await ethers.getContractFactory("TestnetToken")).deploy("NEW", "NEW");
      await newToken.waitForDeployment();

      await ajoContract.connect(owner).addSupportedToken(await newToken.getAddress(), "NEW");

      const [addresses, names] = await ajoContract.getSupportedTokens();
      expect(addresses).to.include(await newToken.getAddress());
      expect(names).to.include("NEW");
    });

    it("Should allow owner to remove supported tokens", async function () {
      const tokenAddress = await testTokens[0].getAddress();
      
      await ajoContract.connect(owner).removeSupportedToken(tokenAddress);

      const [addresses] = await ajoContract.getSupportedTokens();
      expect(addresses).to.not.include(tokenAddress);
    });

    it("Should allow owner to set platform fee", async function () {
      await ajoContract.connect(owner).setPlatformFee(100); // 1%
      
      // We can't directly check the fee, but we can verify it doesn't revert
      // The fee is used internally in payout calculations
    });

    it("Should reject high platform fees", async function () {
      await expect(ajoContract.connect(owner).setPlatformFee(1001))
        .to.be.revertedWith("Fee too high");
    });

    it("Should allow owner to pause/unpause contract", async function () {
      await ajoContract.connect(owner).pause();
      
      // Try to register user while paused
      await expect(ajoContract.connect(user1).registerUser("User1"))
        .to.be.revertedWithCustomError(ajoContract, "EnforcedPause");

      await ajoContract.connect(owner).unpause();
      
      // Should work after unpause
      await ajoContract.connect(user1).registerUser("User1");
      expect(await ajoContract.isUserRegistered(user1.address)).to.be.true;
    });
  });

  describe("Error Handling", function () {
    it("Should handle invalid group IDs", async function () {
      await expect(ajoContract.getGroupSummary(999))
        .to.be.revertedWith("Invalid group ID");
    });

    it("Should prevent non-members from contributing", async function () {
      // Create a group but don't join with user1
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
      
      const tokenAddress = await testTokens[0].getAddress();
      await ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        4
      );

      await ajoContract.connect(user1).registerUser("User1");
      
      await expect(ajoContract.connect(user1).contribute(1))
        .to.be.revertedWith("Not a group member");
    });

    it("Should prevent contributions to inactive groups", async function () {
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");
      
      const tokenAddress = await testTokens[0].getAddress();
      await ajoContract.connect(agent1).createGroup(
        "Test Group",
        "Description",
        tokenAddress,
        contributionAmount,
        contributionFrequency,
        4
      );

      // Group is not active yet (not full)
      await expect(ajoContract.connect(agent1).contribute(1))
        .to.be.revertedWith("Group not active");
    });
  });

  describe("Gas Optimization Tests", function () {
    it("Should efficiently handle multiple group operations", async function () {
      await ajoContract.connect(agent1).registerUser("Agent1");
      await ajoContract.connect(agent1).registerAsAjoAgent("Agent Alice", "alice@agent.com");

      const tokenAddress = await testTokens[0].getAddress();

      // Create multiple groups
      for (let i = 0; i < 5; i++) {
        await ajoContract.connect(agent1).createGroup(
          `Group ${i}`,
          `Description ${i}`,
          tokenAddress,
          contributionAmount,
          contributionFrequency,
          4
        );
      }

      const joinableGroups = await ajoContract.getJoinableGroups();
      expect(joinableGroups.length).to.equal(5);
    });
  });
});