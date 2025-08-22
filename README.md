# BondFi Smart Contract Suite

BondFi is a comprehensive decentralized platform for rotational savings, agent management, and merchant installment contracts, designed to empower communities and merchants with secure, flexible financial tools on Ethereum-compatible blockchains.

## 🌟 Overview

BondFi enables a complete ecosystem of decentralized financial services:

- **🔄 Rotational Savings (Ajo/Esusu):** Create and manage savings groups with customizable parameters
- **💱 Multi-Currency Support:** Deposit and payout in various stablecoins and local tokens with automatic conversion
- **👥 Agent Management:** Register, track, and incentivize trusted agents
- **🛒 Merchant Installment System:** Complete e-commerce solution with flexible installment plans
- **📦 Product Catalog:** Comprehensive product listing, inventory management, and search functionality
- **🔒 Security:** Built with OpenZeppelin libraries for robust access control and protection

## 🏗️ Architecture

The BondFi ecosystem consists of interconnected smart contracts that work together to provide comprehensive financial services:

```
┌─────────────────────────────────────────────────────────────────┐
│                        BondFi Architecture                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────┐    ┌──────────────────────────────────┐    │
│  │   Frontend       │    │       External Integrations     │    │
│  │   Application    │◄──►│   • Swap Protocols              │    │
│  └─────────────────┘    │   • Price Feeds                  │    │
│           │              │                                 │    │
│           ▼              └──────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Core Smart Contracts                       │    │
│  │                                                         │    │
│  │  ┌─────────────────┐  ┌──────────────────────────────┐  │    │
│  │  │ RotationalSaving│  │   MultiCurrencySavingWrapper │  │    │
│  │  │     (Core)      │◄─┤        (Enhanced)           │  │    │
│  │  └─────────────────┘  └──────────────────────────────┘  │    │
│  │           │                          │                  │    │
│  │           ▼                          ▼                  │    │
│  │  ┌─────────────────────────────────────────────────────┐  │    │
│  │  │              Merchant Services                      │  │    │
│  │  │  ┌─────────────┐ ┌──────────────┐ ┌─────────────┐  │  │    │
│  │  │  │MerchantCore │ │ProductCatalog│ │Installment  │  │  │    │
│  │  │  │             │ │              │ │Manager      │  │  │    │
│  │  │  └─────────────┘ └──────────────┘ └─────────────┘  │  │    │
│  │  └─────────────────────────────────────────────────────┘  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Core Contracts

#### 1. Rotational Savings System
- **`RotationalSaving.sol`**: Core contract managing savings groups, contributions, and payouts
- **`SavingLibrary.sol`**: Utility libraries for group management, agent operations, and view functions

#### 2. Multi-Currency Wrapper
- **`MultiCurrencySavingWrapper.sol`**: Advanced wrapper that adds multi-currency support to the core savings contract

**Key Features:**
- **Automatic Currency Conversion**: Users can contribute in their preferred local stablecoin (cNGN, cZAR, cGHS, cKES) while the group operates in a unified base currency (typically USDT)
- **Swap Integration**: Leverages external swap contracts for real-time currency conversion
- **Trusted Contract System**: Uses on-behalf functions to maintain user identity while providing seamless currency conversion
- **Flexible Payout**: Members can receive payouts in their preferred currency, automatically converted from the group's base currency

**Supported Currencies:**
```solidity
// Example supported tokens
USDT - Tether USD (Base currency)
WETH - Wrapped Ethereum  
AFR - AfriRemit
AFX - AfriStable
cNGN - Crypto Naira
cZAR - Crypto South African Rand
cGHS - Crypto Ghanaian Cedi
cKES - Crypto Kenyan Shilling
```

#### 3. Merchant Installment System
A complete e-commerce and installment management system:

- **`MerchantRegistry.sol`**: Merchant onboarding, verification, and reputation management
- **`ProductCatalog.sol`**: Product listing, inventory, categorization, and search
- **`InstallmentManager.sol`**: Installment plan creation, payment processing, and eligibility assessment
- **`MerchantInstallmentCore.sol`**: Main orchestration contract that coordinates all merchant operations

**Merchant System Features:**

**For Merchants:**
- Business registration with category classification
- Multi-token payment acceptance
- Product listing with rich metadata (images, descriptions, categories)
- Inventory management
- Flexible installment plan configuration
- Real-time sales analytics and reputation tracking

**For Customers:**
- Browse products by category or search
- Direct purchase or installment options
- Credit eligibility assessment based on Ajo participation history
- Flexible down payment and installment terms
- Payment tracking and history

**Installment Plan Features:**
- Configurable down payment requirements (minimum percentages)
- Flexible payment frequencies (weekly, bi-weekly, monthly)
- Late payment penalties
- Early payment incentives
- Credit scoring based on savings group participation

## 🔧 Technical Implementation

### Multi-Currency Conversion Flow

1. **User Contribution**: User deposits in their preferred currency (e.g., cNGN)
2. **Automatic Swap**: Wrapper contract calls swap contract to convert to base currency (USDT)
3. **Group Contribution**: Converted amount is contributed to the underlying Ajo group
4. **Payout Conversion**: When claiming, the process reverses - base currency is swapped to user's preferred payout currency

### Price Feed Integration

The system integrates with Chainlink price feeds for accurate currency conversions:

```solidity
// Price feed integration for swap calculations
interface ISwap {
    function swap(address fromToken, address toToken, uint256 amount) 
        external returns (uint256);
}
```

### Trusted Contract System

The MultiCurrencySavingWrapper uses a trusted contract pattern:
- Must be registered as trusted via `addTrustedContract()` 
- Enables on-behalf operations while maintaining user identity
- Provides seamless UX while preserving security

## 📁 Directory Structure

```
contracts/
├── core/
│   ├── Saving.sol                          # Core rotational savings
│   ├── SavingLibrary.sol                   # Utility libraries
│   └── wrapper/
│       └── MultiCurrencySavingWrapper.sol  # Multi-currency support
├── merchant-installable-contracts/
│   ├── InstallmentManager.sol              # Payment plan management
│   ├── MerchantInstallmentCore.sol         # Main orchestration
│   ├── MerchantRegistry.sol                # Merchant onboarding
│   └── ProductCatalog.sol                  # Product management
├── feeds/
│   ├── TestPriceFeed.sol                   # Price feed testing
│   └── MockV3Aggregator.sol                # Chainlink mock
├── interfaces/                             # Contract interfaces
├── libraries/                              # Shared libraries
└── tokens/                                 # Token contracts

scripts/
├── deploy-saving-lisk.js                   # Lisk deployment
└── deploy-saving-mantle.js                 # Mantle deployment


test/
├── Saving.test.js                          # Core savings tests

```

## 🚀 Getting Started

### Prerequisites

- Node.js 16+ & npm
- Hardhat development environment
- MetaMask or compatible wallet
- Access to supported networks (Lisk, Mantle, etc.)

### Installation

```bash
git clone https://github.com/Abuhaneeph/BondFi-smartcontracts.git
cd BondFi-Smart-Contract
npm install
```

### Environment Setup

Create `.env` file:
```env
PRIVATE_KEY=your_private_key
MANTLE_RPC_URL=https://rpc.mantle.xyz

```

### Compilation

```bash
npx hardhat compile
```

### Deployment

#### Core Savings System
```bash


# Deploy to Mantle  
npx hardhat run scripts/deploy-saving-mantle.js --network mantleSeplia
```

#### Merchant System
```bash
npx hardhat run scripts/deploy-merchant-system.js --network <network>
```

### Testing

```bash
# Run all tests
npx hardhat test

# Test specific contracts
npx hardhat test test/Saving.test.js
npx hardhat test test/MultiCurrency.test.js
npx hardhat test test/Merchant.test.js
```

## 🎯 Usage Examples

### Creating a Multi-Currency Savings Group

```javascript
const wrapper = await MultiCurrencySavingWrapper.at(wrapperAddress);

// Create group with USDT as base currency
const groupId = await wrapper.createMultiCurrencyGroup(
    "Community Savings", 
    "Monthly savings group",
    usdtAddress,        // base token
    ethers.utils.parseEther("100"), // contribution amount
    2592000,            // monthly frequency (30 days)
    10                  // max members
);
```

### Joining with Preferred Currency

```javascript
// User joins and sets cNGN as preferred payout currency
await wrapper.joinMultiCurrencyGroup(
    groupId,
    "INVITE123", 
    cNgnAddress  // preferred payout token
);
```

### Contributing in Local Currency

```javascript
// User contributes 15,000 cNGN, automatically converted to USDT
await cNgnToken.approve(wrapper.address, parseEther("15000"));
await wrapper.contributeMultiCurrency(
    groupId,
    cNgnAddress,
    parseEther("15000")
);
```

### Merchant Product Listing

```javascript
const merchantCore = await MerchantInstallmentCore.at(coreAddress);

// Register as merchant
await merchantCore.registerMerchant(
    "Tech Store",
    "contact@techstore.com", 
    "Electronics",
    [usdtAddress, cNgnAddress] // accepted tokens
);

// List product with installment support
await merchantCore.listProduct(
    "iPhone 15 Pro",
    "Latest iPhone model",
    "Electronics", 
    "https://image-url.com/iphone.jpg",
    parseEther("1200"), // price in USDT
    [usdtAddress, cNgnAddress], // accepted tokens
    true,               // allow installments
    2000,              // 20% minimum down payment
    12,                // max 12 installments  
    2592000,           // monthly payments
    50                 // initial stock
);
```

### Purchase with Installments

```javascript
// Customer purchases with 6-month installment plan
await merchantCore.purchaseProductWithInstallments(
    productId,
    usdtAddress,       // payment token
    1,                 // quantity
    parseEther("300"), // down payment (25%)
    6                  // 6 installments
);
```

## 🔒 Security Features

### Access Control
- **Ownable**: Critical functions restricted to contract owners
- **Pausable**: Emergency pause functionality
- **ReentrancyGuard**: Protection against reentrancy attacks

### Multi-Currency Security
- **Trusted Contract Validation**: Wrapper must be explicitly trusted
- **Slippage Protection**: Swap operations include slippage controls
- **Token Validation**: Only whitelisted tokens accepted

### Merchant System Security
- **Merchant Verification**: Registration and reputation system
- **Stock Management**: Prevents overselling
- **Payment Validation**: Multi-step payment verification
- **Installment Protection**: Credit checks and penalty systems

 |

## 📊 Contract Addresses


### Mantle Network  
```
Savings Core: 0xC0c182d9895882C61C1fC1DF20F858e5E29a4f71
Swap Contract: 0x013b0CA4E4559339F43682B7ac05479eD48E694f
USDT: 0x6765e788d5652E22691C6c3385c401a9294B9375
Price Feed: 0xF34EC7483183b0B50E7b50e538ADd13De231eD9b
Multi-Currency Saving: 0x63e5A563F9b4009cbf61EDFcc85f883dbd1b833A
```

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Development Guidelines
- Follow Solidity style guide
- Add comprehensive tests for new features
- Update documentation
- Ensure all tests pass before submitting

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.



## ⚠️ Disclaimer

This software is provided "as is" without warranty. Users should conduct their own security audits before using in production. The developers are not responsible for any losses incurred through the use of these contracts.

---

**BondFi** - Empowering communities through decentralized savings and commerce.
