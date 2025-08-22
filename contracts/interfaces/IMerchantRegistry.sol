// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IMerchantRegistry {
    struct Merchant {
        address merchantAddress;
        string businessName;
        string contactInfo;
        string businessCategory;
        bool isActive;
        uint256 registrationDate;
        uint256 totalSales;
        uint256 completedOrders;
        uint256 disputedOrders;
        uint256 reputationScore;
        address[] acceptedTokens;
    }

    event MerchantRegistered(address indexed merchant, string businessName, string category);
    event MerchantDeactivated(address indexed merchant, string reason);

    function registerMerchant(
        string memory _businessName,
        string memory _contactInfo,
        string memory _businessCategory,
        address[] memory _acceptedTokens
    ) external;

    function getMerchantInfo(address _merchant) external view returns (Merchant memory);
    function isRegisteredMerchant(address _merchant) external view returns (bool);
    function isActiveMerchant(address _merchant) external view returns (bool);
    function merchantSupportsToken(address _merchant, address _token) external view returns (bool);
    function updateMerchantStats(address _merchant, uint256 _saleAmount, bool _completed) external;
    function getAllMerchants() external view returns (address[] memory);
    function deactivateMerchant(address _merchant, string memory _reason) external;
}
