// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/ISavings.sol";
import "../../interfaces/ISwap.sol";


/*
[
  "0x6765e788d5652E22691C6c3385c401a9294B9375", 
  "0x25a8e2d1e9883D1909040b6B3eF2bb91feAB2e2f", 
  "0xC7d68ce9A8047D4bF64E6f7B79d388a11944A06E", 
  "0xCcD4D22E24Ab5f9FD441a6E27bC583d241554a3c", 
  "0x48D2210bd4E72c741F74E6c0E8f356b2C36ebB7A", 
  "0x7dd1aD415F58D91BbF76BcC2640cc6FdD44Aa94b", 
  "0x8F11F588B1Cc0Bc88687F7d07d5A529d34e5CD84", 
  "0xaC56E37f70407f279e27cFcf2E31EdCa888EaEe4"  
]

swapAddress  0x013b0CA4E4559339F43682B7ac05479eD48E694f

SAVING ADDRESS 0xC0c182d9895882C61C1fC1DF20F858e5E29a4f71


0x6765e788d5652E22691C6c3385c401a9294B9375  // USDT

[
  "Tether USD",
  "Wrapped Ethereum",
  "AfriRemit",
  "AfriStable",
  "Crypto Naira",
  "Crypto South African Rand",
  "Crypto Ghanaian Cedi",
  "Crypto Kenyan Shilling"
]

[
  "USDT",
  "WETH",
  "AFR",
  "AFX",
  "cNGN",
  "cZAR",
  "cGHS",
  "cKES"
]

*/

/**
 * @title MultiCurrencySavingWrapper
 * @dev Wrapper contract that adds multi-currency support to existing AjoEsusuSavings contract
 * Allows users to deposit in their local stablecoin and auto-converts to group's base currency
 */
contract MultiCurrencySavingWrapper is ReentrancyGuard, Ownable {
    
    struct MultiCurrencyGroup {
        uint256 ajoGroupId; // ID in the original Ajo contract
        address baseToken; // The unified token used in the actual Ajo group (e.g., USDT)
        bool isActive;
        mapping(address => address) memberPreferredToken; // member => preferred payout token
        mapping(address => bool) isMember;
        address[] members;
        uint256 totalMembers;
    }
    
    struct SupportedCurrency {
        address tokenAddress;
        string name;
        string symbol;
        bool isActive;
    }
    
    // State variables
    IAjoEsusuSavings public immutable ajoContract;
    ISwap public immutable swapContract;
    
    uint256 public nextWrapperGroupId = 1;
    address public immutable USDT; // Set during deployment, immutable default base token
    
    // Supported currencies
    mapping(string => SupportedCurrency) public supportedCurrencies;
    string[] public currencySymbols;
    
    // Group mappings
    mapping(uint256 => MultiCurrencyGroup) public multiCurrencyGroups;
    mapping(uint256 => uint256) public ajoGroupToWrapperGroup; // Maps Ajo group ID to wrapper group ID
    mapping(address => uint256[]) public userGroups;
    
    // Events
    event MultiCurrencyGroupCreated(
        uint256 indexed wrapperGroupId, 
        uint256 indexed ajoGroupId, 
        address indexed creator,
        address baseToken
    );
    
    event MemberJoinedMultiCurrency(
        uint256 indexed wrapperGroupId,
        address indexed member,
        address preferredToken
    );
    
    event CurrencyConverted(
        address indexed user,
        address fromToken,
        address toToken,
        uint256 fromAmount,
        uint256 toAmount
    );
    
    event ContributionMadeMultiCurrency(
        uint256 indexed wrapperGroupId,
        address indexed member,
        address depositToken,
        uint256 depositAmount,
        uint256 convertedAmount
    );
    
    event PayoutClaimedMultiCurrency(
        uint256 indexed wrapperGroupId,
        address indexed member,
        address payoutToken,
        uint256 baseAmount,
        uint256 convertedAmount
    );
    
    constructor(
        address _ajoContract, 
        address _swapContract,
        address _defaultUSDT,
        address[] memory _supportedTokens,
        string[] memory _tokenSymbols,
        string[] memory _tokenNames
    ) Ownable(msg.sender) {
        require(_supportedTokens.length == _tokenSymbols.length, "Tokens and symbols length mismatch");
        require(_supportedTokens.length == _tokenNames.length, "Tokens and names length mismatch");
        require(_defaultUSDT != address(0), "Invalid USDT address");
        
        ajoContract = IAjoEsusuSavings(_ajoContract);
        swapContract = ISwap(_swapContract);
        
        // Set USDT as default base currency (always supported)
        USDT = _defaultUSDT;
        _addSupportedCurrency("USDT", _defaultUSDT, "Tether USD");
        
        // Initialize supported currencies from parameters
        for (uint256 i = 0; i < _supportedTokens.length; i++) {
            if (_supportedTokens[i] != _defaultUSDT) { // Avoid duplicating USDT
                _addSupportedCurrency(_tokenSymbols[i], _supportedTokens[i], _tokenNames[i]);
            }
        }
    }
    
    /**
 * @dev Owner function to register this contract as trusted with AjoEsusuSavings
 * Must be called after deployment by the owner
 */
function registerAsTrustedContract() external onlyOwner {
    // The AjoEsusuSavings contract owner needs to call addTrustedContract(address(this))
    // This function serves as a reminder/documentation
    revert("Owner of AjoEsusuSavings must call addTrustedContract() with this wrapper address");
}
   

/**
 * @dev Updated create multi-currency group function
 */
function createMultiCurrencyGroup(
    string memory _name,
    string memory _description,
    address _baseToken,
    uint256 _contributionAmount,
    uint256 _contributionFrequency,
    uint256 _maxMembers
) external returns (uint256) {
    require(_isTokenSupported(_baseToken), "Base token not supported");
    
    // Create group in the original Ajo contract using the new on-behalf function
    uint256 ajoGroupId = ajoContract.createGroupOnBehalf(
        msg.sender, // Pass the actual user as creator
        _name,
        _description,
        _baseToken,
        _contributionAmount,
        _contributionFrequency,
        _maxMembers
    );
    
    // Create wrapper group
    uint256 wrapperGroupId = nextWrapperGroupId++;
    MultiCurrencyGroup storage group = multiCurrencyGroups[wrapperGroupId];
    group.ajoGroupId = ajoGroupId;
    group.baseToken = _baseToken;
    group.isActive = true;
    
    // Map the relationship
    ajoGroupToWrapperGroup[ajoGroupId] = wrapperGroupId;
    userGroups[msg.sender].push(wrapperGroupId);
    
    emit MultiCurrencyGroupCreated(wrapperGroupId, ajoGroupId, msg.sender, _baseToken);
    return wrapperGroupId;
}

/**
 * @dev Updated join multi-currency group with preferred payout currency
 */
function joinMultiCurrencyGroup(
    uint256 _wrapperGroupId,
    string memory _inviteCode,
    address _preferredToken
) external {
    require(_isTokenSupported(_preferredToken), "Preferred token not supported");
    require(multiCurrencyGroups[_wrapperGroupId].isActive, "Group not active");
    require(!multiCurrencyGroups[_wrapperGroupId].isMember[msg.sender], "Already a member");
    
    MultiCurrencyGroup storage group = multiCurrencyGroups[_wrapperGroupId];
    
    // Join the original Ajo group using the on-behalf function
    ajoContract.joinGroupWithCodeOnBehalf(msg.sender, group.ajoGroupId, _inviteCode);
    
    // Add to wrapper group
    group.memberPreferredToken[msg.sender] = _preferredToken;
    group.isMember[msg.sender] = true;
    group.members.push(msg.sender);
    group.totalMembers++;
    
    userGroups[msg.sender].push(_wrapperGroupId);
    
    emit MemberJoinedMultiCurrency(_wrapperGroupId, msg.sender, _preferredToken);
}

/**
 * @dev Updated make contribution in any supported currency
 */
function contributeMultiCurrency(
    uint256 _wrapperGroupId,
    address _depositToken,
    uint256 _depositAmount
) external nonReentrant {
    require(_isTokenSupported(_depositToken), "Deposit token not supported");
    require(multiCurrencyGroups[_wrapperGroupId].isMember[msg.sender], "Not a member");
    
    MultiCurrencyGroup storage group = multiCurrencyGroups[_wrapperGroupId];
    
    uint256 convertedAmount;
    
    if (_depositToken == group.baseToken) {
        // No conversion needed
        convertedAmount = _depositAmount;
        IERC20(_depositToken).transferFrom(msg.sender, address(this), _depositAmount);
    } else {
        // Convert to base token
        IERC20(_depositToken).transferFrom(msg.sender, address(this), _depositAmount);
        
        // Approve swap contract to spend tokens
        IERC20(_depositToken).approve(address(swapContract), _depositAmount);
        
        // Perform swap
        convertedAmount = swapContract.swap(_depositToken, group.baseToken, _depositAmount);
        
        emit CurrencyConverted(msg.sender, _depositToken, group.baseToken, _depositAmount, convertedAmount);
    }
    
    // Approve Ajo contract to spend base tokens (since we're calling on their behalf)
    IERC20(group.baseToken).approve(address(ajoContract), convertedAmount);
    
    // Contribute to original Ajo group using on-behalf function
    ajoContract.contributeOnBehalf(msg.sender, group.ajoGroupId, convertedAmount);
    
    emit ContributionMadeMultiCurrency(_wrapperGroupId, msg.sender, _depositToken, _depositAmount, convertedAmount);
}

/**
 * @dev Updated claim payout in preferred currency
 */
function claimMultiCurrencyPayout(uint256 _wrapperGroupId) external nonReentrant {
    require(multiCurrencyGroups[_wrapperGroupId].isMember[msg.sender], "Not a member");
    
    MultiCurrencyGroup storage group = multiCurrencyGroups[_wrapperGroupId];
    address preferredToken = group.memberPreferredToken[msg.sender];
    
    // Claim from original Ajo contract using on-behalf function
    // This will transfer the payout to this wrapper contract
    uint256 payoutAmount = ajoContract.claimPayoutOnBehalf(msg.sender, group.ajoGroupId);
    
    uint256 convertedAmount;
    
    if (preferredToken == group.baseToken) {
        // No conversion needed
        convertedAmount = payoutAmount;
        IERC20(group.baseToken).transfer(msg.sender, payoutAmount);
    } else {
        // Convert to preferred token
        IERC20(group.baseToken).approve(address(swapContract), payoutAmount);
        convertedAmount = swapContract.swap(group.baseToken, preferredToken, payoutAmount);
        
        // Transfer converted amount to user
        IERC20(preferredToken).transfer(msg.sender, convertedAmount);
        
        emit CurrencyConverted(msg.sender, group.baseToken, preferredToken, payoutAmount, convertedAmount);
    }
    
    emit PayoutClaimedMultiCurrency(_wrapperGroupId, msg.sender, preferredToken, payoutAmount, convertedAmount);
}

/**
 * @dev Helper function to check if wrapper is registered as trusted
 */
function isTrustedContract() external view returns (bool) {
    return ajoContract.isTrustedContract(address(this));
}

/**
 * @dev Emergency function if wrapper loses trusted status
 */
function requestTrustedStatus() external view onlyOwner {
    require(!ajoContract.isTrustedContract(address(this)), "Already trusted");
    revert("AjoEsusuSavings owner must call addTrustedContract() with this wrapper address");
}

   
    
    /**
     * @dev Get multi-currency group details
     */
    function getMultiCurrencyGroupDetails(uint256 _wrapperGroupId) external view returns (
        uint256 ajoGroupId,
        address baseToken,
        bool isActive,
        uint256 totalMembers,
        address[] memory members,
        address userPreferredToken
    ) {
        MultiCurrencyGroup storage group = multiCurrencyGroups[_wrapperGroupId];
        return (
            group.ajoGroupId,
            group.baseToken,
            group.isActive,
            group.totalMembers,
            group.members,
            group.memberPreferredToken[msg.sender]
        );
    }
    
    /**
     * @dev Add supported currency (owner only)
     */
    function addSupportedCurrency(
        string memory _symbol,
        address _tokenAddress,
        string memory _name
    ) external onlyOwner {
        _addSupportedCurrency(_symbol, _tokenAddress, _name);
    }
    
    /**
     * @dev Remove supported currency (owner only)
     */
    function removeSupportedCurrency(string memory _symbol) external onlyOwner {
        supportedCurrencies[_symbol].isActive = false;
    }
    
    /**
     * @dev Internal function to add supported currency
     */
    function _addSupportedCurrency(
        string memory _symbol,
        address _tokenAddress,
        string memory _name
    ) internal {
        supportedCurrencies[_symbol] = SupportedCurrency({
            tokenAddress: _tokenAddress,
            name: _name,
            symbol: _symbol,
            isActive: true
        });
        
        // Add to symbols array if not already present
        bool exists = false;
        for (uint i = 0; i < currencySymbols.length; i++) {
            if (keccak256(bytes(currencySymbols[i])) == keccak256(bytes(_symbol))) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            currencySymbols.push(_symbol);
        }
    }
    
    /**
     * @dev Check if token is supported
     */
    function _isTokenSupported(address _token) internal view returns (bool) {
        for (uint i = 0; i < currencySymbols.length; i++) {
            if (supportedCurrencies[currencySymbols[i]].tokenAddress == _token && 
                supportedCurrencies[currencySymbols[i]].isActive) {
                return true;
            }
        }
        return false;
    }
    
    /**
     * @dev Get all supported currencies
     */
    function getSupportedCurrencies() external view returns (
        string[] memory symbols,
        address[] memory addresses,
        string[] memory names
    ) {
        uint256 activeCount = 0;
        
        // Count active currencies
        for (uint i = 0; i < currencySymbols.length; i++) {
            if (supportedCurrencies[currencySymbols[i]].isActive) {
                activeCount++;
            }
        }
        
        symbols = new string[](activeCount);
        addresses = new address[](activeCount);
        names = new string[](activeCount);
        
        uint256 index = 0;
        for (uint i = 0; i < currencySymbols.length; i++) {
            if (supportedCurrencies[currencySymbols[i]].isActive) {
                symbols[index] = currencySymbols[i];
                addresses[index] = supportedCurrencies[currencySymbols[i]].tokenAddress;
                names[index] = supportedCurrencies[currencySymbols[i]].name;
                index++;
            }
        }
        
        return (symbols, addresses, names);
    }
    
    /**
     * @dev Emergency function to withdraw stuck tokens (owner only)
     */
    function emergencyWithdraw(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(owner(), _amount);
    }
}


/*

===================LISK ============================
  swapAddress 0xdf4381E3D3D040575f297F7478BD5D71ca97Aeac

  ajo  0xe85b044a579e8787afFfBF46691a01E7052cF6D0

  USDT   0x88a4e1125FF42e0010192544EAABd78Db393406e

  [
  "0x88a4e1125FF42e0010192544EAABd78Db393406e", 
  "0xa01ada077F5C2DB68ec56f1a28694f4d495201c9", 
  "0x207d9E20755fEe1924c79971A3e2d550CE6Ff2CB", 
  "0xc5737615ed39b6B089BEDdE11679e5e1f6B9E768", 
  "0x278ccC9E116Ac4dE6c1B2Ba6bfcC81F25ee48429", 
  "0x1255C3745a045f653E5363dB6037A2f854f58FBf", 
  "0x19a8a27E066DD329Ed78F500ca7B249D40241dC4", 
  "0x291ca1891b41a25c161fDCAE06350E6a524068d5"  
]

[
  "USDT",
  "Wrapped Ethereum",
  "AfriRemit",
  "AfriStable",
  "Crypto Naira",
  "Crypto South African Rand",
  "Crypto Ghanaian Cedi",
  "Crypto Kenyan Shilling"
]

[
  "USDT",
  "WETH",
  "AFR",
  "AFX",
  "cNGN",
  "cZAR",
  "cGHS",
  "cKES"
]




*/