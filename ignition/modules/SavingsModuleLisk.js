// scripts/deploy-savings.js
const hre = require("hardhat");

async function main() {
  console.log("Deploying AjoEsusuSavings contract to Mantle Sepolia...");

  // Contract parameters (same as your Ignition module)
  const tokenNames = ["USDT", "WETH", "AFR", "AFX", "cNGN", "cGHS", "cZAR", "cKES"];
  
  const TokensAddresses =   [
  "0x88a4e1125FF42e0010192544EAABd78Db393406e", 
  "0xa01ada077F5C2DB68ec56f1a28694f4d495201c9", 
  "0x207d9E20755fEe1924c79971A3e2d550CE6Ff2CB", 
  "0xc5737615ed39b6B089BEDdE11679e5e1f6B9E768", 
  "0x278ccC9E116Ac4dE6c1B2Ba6bfcC81F25ee48429", 
  "0x1255C3745a045f653E5363dB6037A2f854f58FBf", 
  "0x19a8a27E066DD329Ed78F500ca7B249D40241dC4", 
  "0x291ca1891b41a25c161fDCAE06350E6a524068d5"  
];

  const swap = '0xdf4381E3D3D040575f297F7478BD5D71ca97Aeac';

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