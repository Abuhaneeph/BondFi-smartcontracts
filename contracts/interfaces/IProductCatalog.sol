// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IProductCatalog {
    struct Product {
        uint256 productId;
        address merchant;
        string merchantName;
        string name;
        string description;
        string category;
        string imageUrl;
        uint256 price;
        address[] acceptedTokens;
        bool isAvailable;
        bool allowInstallments;
        uint256 minDownPaymentRate;
        uint256 maxInstallments;
        uint256 installmentFrequency;
        uint256 stock;
        uint256 totalSold;
        uint256 createdAt;
        uint256 updatedAt;
    }

    struct ProductSummary {
        uint256 productId;
        address merchant;
        string merchantName;
        string name;
        string description;
        string category;
        string imageUrl;
        uint256 price;
        address[] acceptedTokens;
        string[] tokenNames;
        bool isAvailable;
        bool allowInstallments;
        uint256 minDownPaymentRate;
        uint256 maxInstallments;
        uint256 stock;
        uint256 merchantReputation;
    }

    event ProductListed(uint256 indexed productId, address indexed merchant, string name, uint256 price, bool allowInstallments);
    event ProductUpdated(uint256 indexed productId, address indexed merchant);
    event ProductDelisted(uint256 indexed productId, address indexed merchant);

    function listProduct(
        address _merchant,
        string memory _name,
        string memory _description,
        string memory _category,
        string memory _imageUrl,
        uint256 _price,
        address[] memory _acceptedTokens,
        bool _allowInstallments,
        uint256 _minDownPaymentRate,
        uint256 _maxInstallments,
        uint256 _installmentFrequency,
        uint256 _initialStock
    ) external returns (uint256);

    function getProduct(uint256 _productId) external view returns (Product memory);
    function getProductSummary(uint256 _productId) external view returns (ProductSummary memory);
    function getAllProducts() external view returns (ProductSummary[] memory);
    function getProductsByCategory(string memory _category) external view returns (ProductSummary[] memory);
    function getMerchantProducts(address _merchant) external view returns (ProductSummary[] memory);
    function searchProducts(string memory _searchTerm) external view returns (ProductSummary[] memory);
    function updateStock(uint256 _productId, uint256 _newStock) external;
    function reserveStock(uint256 _productId, uint256 _quantity) external;
    function updateProduct(uint256 _productId, string memory _name, string memory _description, string memory _imageUrl, uint256 _price, bool _isAvailable, uint256 _stock) external;
    function delistProduct(uint256 _productId) external;
}
