// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../interfaces/IAjoEsusuSavings.sol";
import "../../interfaces/IProductCatalog.sol";
import "../../interfaces/IMerchantRegistry.sol";

contract ProductCatalog is IProductCatalog, Ownable, Pausable {
    IAjoEsusuSavings public immutable ajoContract;
    IMerchantRegistry public immutable merchantRegistry;
    
    uint256 public nextProductId = 1;
    uint256 public constant MIN_DOWN_PAYMENT_RATE = 1000; // 10%
    uint256 public constant MAX_INSTALLMENTS = 12;
    uint256 public constant MIN_INSTALLMENT_FREQUENCY = 86400; // 1 day

    mapping(uint256 => Product) public products;
    mapping(address => bool) public authorizedContracts;
    mapping(string => uint256[]) public productsByCategory;
    uint256[] public allProducts;

    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier onlyActiveMerchant(address _merchant) {
        require(merchantRegistry.isActiveMerchant(_merchant), "Not an active merchant");
        _;
    }

    constructor(address _ajoContract, address _merchantRegistry) Ownable(msg.sender) {
        require(_ajoContract != address(0), "Invalid Ajo contract address");
        require(_merchantRegistry != address(0), "Invalid merchant registry address");
        ajoContract = IAjoEsusuSavings(_ajoContract);
        merchantRegistry = IMerchantRegistry(_merchantRegistry);
    }

    function setAuthorizedContract(address _contract, bool _authorized) external onlyOwner {
        authorizedContracts[_contract] = _authorized;
    }

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
    ) external onlyAuthorized onlyActiveMerchant(_merchant) whenNotPaused returns (uint256) {
        require(bytes(_name).length > 0 && bytes(_name).length <= 100, "Invalid product name");
        require(bytes(_description).length > 0 && bytes(_description).length <= 500, "Invalid description");
        require(bytes(_category).length > 0 && bytes(_category).length <= 50, "Invalid category");
        require(_price > 0, "Price must be greater than 0");
        require(_acceptedTokens.length > 0, "Must accept at least one token");
        require(_initialStock > 0, "Initial stock must be greater than 0");

        if (_allowInstallments) {
            require(_minDownPaymentRate >= MIN_DOWN_PAYMENT_RATE, "Down payment rate too low");
            require(_minDownPaymentRate <= 5000, "Down payment rate too high");
            require(_maxInstallments >= 2 && _maxInstallments <= MAX_INSTALLMENTS, "Invalid max installments");
            require(_installmentFrequency >= MIN_INSTALLMENT_FREQUENCY, "Installment frequency too short");
        }

        /*

        // Verify merchant accepts all specified tokens
        for (uint256 i = 0; i < _acceptedTokens.length; i++) {
            require(merchantRegistry.merchantSupportsToken(_merchant, _acceptedTokens[i]), "Token not accepted by merchant");
        }
        */

        uint256 productId = nextProductId++;
        IMerchantRegistry.Merchant memory merchantInfo = merchantRegistry.getMerchantInfo(_merchant);

        products[productId] = Product({
            productId: productId,
            merchant: _merchant,
            merchantName: merchantInfo.businessName,
            name: _name,
            description: _description,
            category: _category,
            imageUrl: _imageUrl,
            price: _price,
            acceptedTokens: _acceptedTokens,
            isAvailable: true,
            allowInstallments: _allowInstallments,
            minDownPaymentRate: _allowInstallments ? _minDownPaymentRate : 0,
            maxInstallments: _allowInstallments ? _maxInstallments : 0,
            installmentFrequency: _allowInstallments ? _installmentFrequency : 0,
            stock: _initialStock,
            totalSold: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        productsByCategory[_category].push(productId);
        allProducts.push(productId);

        emit ProductListed(productId, _merchant, _name, _price, _allowInstallments);
        return productId;
    }

    function getProduct(uint256 _productId) external view returns (Product memory) {
        require(_productId > 0 && _productId < nextProductId, "Invalid product ID");
        return products[_productId];
    }

    function getProductSummary(uint256 _productId) external view returns (ProductSummary memory) {
        require(_productId > 0 && _productId < nextProductId, "Invalid product ID");
        return _getProductSummary(_productId);
    }

    function _getProductSummary(uint256 _productId) internal view returns (ProductSummary memory) {
        Product storage product = products[_productId];
        IMerchantRegistry.Merchant memory merchantInfo = merchantRegistry.getMerchantInfo(product.merchant);

        // Get token names
        string[] memory tokenNames = new string[](product.acceptedTokens.length);
        for (uint256 i = 0; i < product.acceptedTokens.length; i++) {
            tokenNames[i] = ajoContract.tokenNames(product.acceptedTokens[i]);
        }

        return ProductSummary({
            productId: _productId,
            merchant: product.merchant,
            merchantName: product.merchantName,
            name: product.name,
            description: product.description,
            category: product.category,
            imageUrl: product.imageUrl,
            price: product.price,
            acceptedTokens: product.acceptedTokens,
            tokenNames: tokenNames,
            isAvailable: product.isAvailable,
            allowInstallments: product.allowInstallments,
            minDownPaymentRate: product.minDownPaymentRate,
            maxInstallments: product.maxInstallments,
            stock: product.stock,
            merchantReputation: merchantInfo.reputationScore
        });
    }

    function getAllProducts() external view returns (ProductSummary[] memory) {
        uint256 availableCount = 0;

        // Count available products
        for (uint256 i = 0; i < allProducts.length; i++) {
            uint256 productId = allProducts[i];
            if (products[productId].isAvailable && products[productId].stock > 0) {
                availableCount++;
            }
        }

        ProductSummary[] memory availableProducts = new ProductSummary[](availableCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allProducts.length; i++) {
            uint256 productId = allProducts[i];
            if (products[productId].isAvailable && products[productId].stock > 0) {
                availableProducts[index] = _getProductSummary(productId);
                index++;
            }
        }

        return availableProducts;
    }

    function getProductsByCategory(string memory _category) external view returns (ProductSummary[] memory) {
        uint256[] memory categoryProducts = productsByCategory[_category];
        uint256 availableCount = 0;

        // Count available products in category
        for (uint256 i = 0; i < categoryProducts.length; i++) {
            uint256 productId = categoryProducts[i];
            if (products[productId].isAvailable && products[productId].stock > 0) {
                availableCount++;
            }
        }

        ProductSummary[] memory availableProducts = new ProductSummary[](availableCount);
        uint256 index = 0;

        for (uint256 i = 0; i < categoryProducts.length; i++) {
            uint256 productId = categoryProducts[i];
            if (products[productId].isAvailable && products[productId].stock > 0) {
                availableProducts[index] = _getProductSummary(productId);
                index++;
            }
        }

        return availableProducts;
    }

    function getMerchantProducts(address _merchant) external view returns (ProductSummary[] memory) {
        uint256 availableCount = 0;

        // Count merchant's available products
        for (uint256 i = 0; i < allProducts.length; i++) {
            uint256 productId = allProducts[i];
            if (products[productId].merchant == _merchant && products[productId].isAvailable) {
                availableCount++;
            }
        }

        ProductSummary[] memory availableProducts = new ProductSummary[](availableCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allProducts.length; i++) {
            uint256 productId = allProducts[i];
            if (products[productId].merchant == _merchant && products[productId].isAvailable) {
                availableProducts[index] = _getProductSummary(productId);
                index++;
            }
        }

        return availableProducts;
    }

    function searchProducts(string memory _searchTerm) external view returns (ProductSummary[] memory) {
        bytes memory searchBytes = bytes(_searchTerm);
        require(searchBytes.length > 0, "Search term cannot be empty");

        uint256 matchCount = 0;

        // First pass: count matches
        for (uint256 i = 0; i < allProducts.length; i++) {
            uint256 productId = allProducts[i];
            Product storage product = products[productId];

            if (product.isAvailable && product.stock > 0) {
                if (_containsIgnoreCase(product.name, _searchTerm) ||
                    _containsIgnoreCase(product.description, _searchTerm) ||
                    _containsIgnoreCase(product.category, _searchTerm)) {
                    matchCount++;
                }
            }
        }

        // Second pass: collect matches
        ProductSummary[] memory matches = new ProductSummary[](matchCount);
        uint256 index = 0;

        for (uint256 i = 0; i < allProducts.length; i++) {
            uint256 productId = allProducts[i];
            Product storage product = products[productId];

            if (product.isAvailable && product.stock > 0) {
                if (_containsIgnoreCase(product.name, _searchTerm) ||
                    _containsIgnoreCase(product.description, _searchTerm) ||
                    _containsIgnoreCase(product.category, _searchTerm)) {
                    matches[index] = _getProductSummary(productId);
                    index++;
                }
            }
        }

        return matches;
    }

    function _containsIgnoreCase(string memory _text, string memory _searchTerm) internal pure returns (bool) {
        bytes memory textBytes = bytes(_text);
        bytes memory searchBytes = bytes(_searchTerm);

        if (searchBytes.length > textBytes.length) return false;
        if (searchBytes.length == 0) return true;

        for (uint256 i = 0; i <= textBytes.length - searchBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchBytes.length; j++) {
                bytes1 textChar = textBytes[i + j];
                bytes1 searchChar = searchBytes[j];

                // Convert to lowercase for comparison
                if (textChar >= 0x41 && textChar <= 0x5A) textChar = bytes1(uint8(textChar) + 32);
                if (searchChar >= 0x41 && searchChar <= 0x5A) searchChar = bytes1(uint8(searchChar) + 32);

                if (textChar != searchChar) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    function updateStock(uint256 _productId, uint256 _newStock) external onlyAuthorized {
        require(_productId > 0 && _productId < nextProductId, "Invalid product ID");
        products[_productId].stock = _newStock;
        products[_productId].updatedAt = block.timestamp;
    }

    function reserveStock(uint256 _productId, uint256 _quantity) external onlyAuthorized {
        require(_productId > 0 && _productId < nextProductId, "Invalid product ID");
        require(products[_productId].stock >= _quantity, "Insufficient stock");
        products[_productId].stock -= _quantity;
        products[_productId].totalSold += _quantity;
        products[_productId].updatedAt = block.timestamp;
    }

    function updateProduct(
        uint256 _productId,
        string memory _name,
        string memory _description,
        string memory _imageUrl,
        uint256 _price,
        bool _isAvailable,
        uint256 _stock
    ) external {
        require(_productId > 0 && _productId < nextProductId, "Invalid product ID");
        Product storage product = products[_productId];
        require(product.merchant == msg.sender, "Not your product");
        require(bytes(_name).length > 0 && bytes(_name).length <= 100, "Invalid product name");
        require(_price > 0, "Price must be greater than 0");

        product.name = _name;
        product.description = _description;
        product.imageUrl = _imageUrl;
        product.price = _price;
        product.isAvailable = _isAvailable;
        product.stock = _stock;
        product.updatedAt = block.timestamp;

        emit ProductUpdated(_productId, msg.sender);
    }

    function delistProduct(uint256 _productId) external {
        require(_productId > 0 && _productId < nextProductId, "Invalid product ID");
        Product storage product = products[_productId];
        require(product.merchant == msg.sender || msg.sender == owner(), "Not authorized");

        product.isAvailable = false;
        product.updatedAt = block.timestamp;

        emit ProductDelisted(_productId, product.merchant);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
