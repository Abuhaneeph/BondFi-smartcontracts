// scripts/deploy-savings.js
const hre = require("hardhat");

async function main() {
  console.log("Deploying AjoEsusuSavings contract to Mantle Sepolia...");

  // Contract parameters (same as your Ignition module)
  const tokenNames = ["USDT", "WETH", "AFR", "AFX", "cNGN", "cGHS", "cZAR", "cKES"];
  
  const TokensAddresses = [
    '0x6765e788d5652E22691C6c3385c401a9294B9375', // USDT
    '0x25a8e2d1e9883D1909040b6B3eF2bb91feAB2e2f', // WETH
    '0xC7d68ce9A8047D4bF64E6f7B79d388a11944A06E', // AFR
    '0xCcD4D22E24Ab5f9FD441a6E27bC583d241554a3c', // AFX
    '0x48D2210bd4E72c741F74E6c0E8f356b2C36ebB7A', // cNGN
    '0x7dd1aD415F58D91BbF76BcC2640cc6FdD44Aa94b', // cZAR
    '0x8F11F588B1Cc0Bc88687F7d07d5A529d34e5CD84', // cGHS
    '0xaC56E37f70407f279e27cFcf2E31EdCa888EaEe4'  // cKES
  ];

  const swap = '0x013b0CA4E4559339F43682B7ac05479eD48E694f';

  // Get deployer account
  const [deployer] = await hre.ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("Account balance:", hre.ethers.formatEther(balance), "MNT");

  // Get contract factory
  const AjoEsusuSavings = await hre.ethers.getContractFactory("AjoEsusuSavingsInitial");

  console.log("\nDeploying AjoEsusuSavings...");
  console.log("Constructor parameters:");
  console.log("- Token Addresses:", TokensAddresses);
  console.log("- Token Names:", tokenNames);
  console.log("- Swap Address:", swap);

  // Deploy contract
  const ajo = await AjoEsusuSavings.deploy(
    TokensAddresses,
    tokenNames,
    {
      gasLimit: 50000000000000000000 // Set reasonable gas limit
    }
  );

  console.log("Waiting for deployment transaction to be mined...");
  await ajo.waitForDeployment();

  const contractAddress = await ajo.getAddress();
  console.log("✅ AjoEsusuSavings deployed successfully!");
  console.log("📄 Contract Address:", contractAddress);
  
  const txHash = ajo.deploymentTransaction().hash;
  console.log("🔗 Transaction Hash:", txHash);

  // Verify contract after a few confirmations
  if (hre.network.name !== "hardhat" && hre.network.name !== "localhost") {
    console.log("\nWaiting for block confirmations...");
    await ajo.deploymentTransaction().wait(3);

    console.log("Attempting to verify contract...");
    try {
      await hre.run("verify:verify", {
        address: contractAddress,
        constructorArguments: [
          TokensAddresses,
          tokenNames
        ],
      });
      console.log("✅ Contract verified successfully!");
    } catch (error) {
      console.log("❌ Verification failed:", error.message);
      console.log("You can manually verify later with:");
      console.log(`npx hardhat verify --network mantleSepolia ${contractAddress} "${TokensAddresses.join('","')}" "${tokenNames.join('","')}" ${swap}`);
    }
  }

  console.log("\n🎉 Deployment completed!");
  console.log("Save this information:");
  console.log("Contract Address:", contractAddress);
  console.log("Transaction Hash:", txHash);
  console.log("Network: Mantle Sepolia (5003)");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });