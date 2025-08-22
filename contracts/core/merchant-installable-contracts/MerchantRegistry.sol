// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../interfaces/IAjoEsusuSavings.sol";
import "../../interfaces/IMerchantRegistry.sol";

contract MerchantRegistry is IMerchantRegistry, Ownable, Pausable {
    //MOCK AJO 0x99895b44d3659e1303aA59EaDba609F22fb8D599
    IAjoEsusuSavings public immutable ajoContract;
    
    mapping(address => Merchant) public merchants;
    mapping(address => bool) public registeredMerchants;
    mapping(address => mapping(address => bool)) public merchantSupportedTokens;
    mapping(address => bool) public authorizedContracts;
    address[] public allMerchants;

    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    constructor(address _ajoContract) Ownable(msg.sender) {
        require(_ajoContract != address(0), "Invalid Ajo contract address");
        ajoContract = IAjoEsusuSavings(_ajoContract);
    }

    function setAuthorizedContract(address _contract, bool _authorized) external onlyOwner {
        authorizedContracts[_contract] = _authorized;
    }

    function registerMerchant(
        string memory _businessName,
        string memory _contactInfo,
        string memory _businessCategory,
        address[] memory _acceptedTokens
    ) external whenNotPaused {
        require(!registeredMerchants[msg.sender], "Already registered");
        require(bytes(_businessName).length > 0 && bytes(_businessName).length <= 100, "Invalid business name");
        require(bytes(_contactInfo).length > 0 && bytes(_contactInfo).length <= 200, "Invalid contact info");
        require(_acceptedTokens.length > 0, "Must accept at least one token");
        

        // Verify all tokens are supported by the Ajo contract
        for (uint256 i = 0; i < _acceptedTokens.length; i++) {
            require(ajoContract.supportedTokens(_acceptedTokens[i]), "Token not supported by Ajo contract");
            merchantSupportedTokens[msg.sender][_acceptedTokens[i]] = true;
        }
  
        merchants[msg.sender] = Merchant({
            merchantAddress: msg.sender,
            businessName: _businessName,
            contactInfo: _contactInfo,
            businessCategory: _businessCategory,
            isActive: true,
            registrationDate: block.timestamp,
            totalSales: 0,
            completedOrders: 0,
            disputedOrders: 0,
            reputationScore: 75,
            acceptedTokens: _acceptedTokens
        });

        registeredMerchants[msg.sender] = true;
        allMerchants.push(msg.sender);

        emit MerchantRegistered(msg.sender, _businessName, _businessCategory);
    }

    function getMerchantInfo(address _merchant) external view returns (Merchant memory) {
        return merchants[_merchant];
    }

    function isRegisteredMerchant(address _merchant) external view returns (bool) {
        return registeredMerchants[_merchant];
    }

    function isActiveMerchant(address _merchant) external view returns (bool) {
        return registeredMerchants[_merchant] && merchants[_merchant].isActive;
    }

    function merchantSupportsToken(address _merchant, address _token) external view returns (bool) {
        return merchantSupportedTokens[_merchant][_token];
    }

    function updateMerchantStats(address _merchant, uint256 _saleAmount, bool _completed) external onlyAuthorized {
        require(registeredMerchants[_merchant], "Merchant not registered");
        
        merchants[_merchant].totalSales += _saleAmount;
        
        if (_completed) {
            merchants[_merchant].completedOrders++;
            // Improve reputation for completed orders
            if (merchants[_merchant].reputationScore < 95) {
                merchants[_merchant].reputationScore += 2;
            }
        } else {
            merchants[_merchant].disputedOrders++;
            // Decrease reputation for disputes
            if (merchants[_merchant].reputationScore > 10) {
                merchants[_merchant].reputationScore -= 5;
            }
        }
    }

    function getAllMerchants() external view returns (address[] memory) {
        return allMerchants;
    }

    function deactivateMerchant(address _merchant, string memory _reason) external onlyOwner {
        require(registeredMerchants[_merchant], "Not a registered merchant");
        merchants[_merchant].isActive = false;
        emit MerchantDeactivated(_merchant, _reason);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
