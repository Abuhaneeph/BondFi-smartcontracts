// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../interfaces/IAjoEsusuSavings.sol";
import "../../interfaces/IMerchantRegistry.sol";
import "../../interfaces/IProductCatalog.sol";
import "../../interfaces/IInstallmentManager.sol";

//MERCHANT REGISTRY 0xE29f69cCeC803F9089A0358d2e3B47118323104d
//INSTALLMENT MANAGER 0x3d19CE4dd54f5CBc54CFf6bc0B4430Ce6Fd00bE3
//PRODUCT CATALOG 0xd14f93aE3ae06Bb5d36684C672702e7F5a3D4B6E
//AJO 0xC0c182d9895882C61C1fC1DF20F858e5E29a4f71
//MERCHANTCORE 0xD182cBE8f2C03d230fcc578811CAf591BFB24e99
contract MerchantInstallmentCore is ReentrancyGuard, Ownable, Pausable {
    IAjoEsusuSavings public immutable ajoContract;
    IMerchantRegistry public immutable merchantRegistry;
    IProductCatalog public immutable productCatalog;
    IInstallmentManager public immutable installmentManager;
    
    uint256 public platformFeePercentage = 100; // 1% (100/10000)
    mapping(address => uint256) public platformFees; // token => accumulated fees

    event ProductPurchased(uint256 indexed productId, address indexed customer, uint256 planId, bool isInstallment);
    event PlatformFeesWithdrawn(address indexed token, uint256 amount);

    constructor(
        address _ajoContract,
        address _merchantRegistry,
        address _productCatalog,
        address _installmentManager
    ) Ownable(msg.sender) {
        require(_ajoContract != address(0), "Invalid Ajo contract address");
        require(_merchantRegistry != address(0), "Invalid merchant registry address");
        require(_productCatalog != address(0), "Invalid product catalog address");
        require(_installmentManager != address(0), "Invalid installment manager address");
        
        ajoContract = IAjoEsusuSavings(_ajoContract);
        merchantRegistry = IMerchantRegistry(_merchantRegistry);
        productCatalog = IProductCatalog(_productCatalog);
        installmentManager = IInstallmentManager(_installmentManager);
    }

    // Merchant functions
    function registerMerchant(
        string memory _businessName,
        string memory _contactInfo,
        string memory _businessCategory,
        address[] memory _acceptedTokens
    ) external whenNotPaused {
        merchantRegistry.registerMerchant(_businessName, _contactInfo, _businessCategory, _acceptedTokens);
    }

    function listProduct(
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
    ) external whenNotPaused returns (uint256) {
        return productCatalog.listProduct(
            msg.sender,
            _name,
            _description,
            _category,
            _imageUrl,
            _price,
            _acceptedTokens,
            _allowInstallments,
            _minDownPaymentRate,
            _maxInstallments,
            _installmentFrequency,
            _initialStock
        );
    }

    // Customer functions
    function purchaseProduct(uint256 _productId, address _paymentToken, uint256 _quantity)
        external
        whenNotPaused
        nonReentrant
    {
        IProductCatalog.Product memory product = productCatalog.getProduct(_productId);
        require(product.isAvailable, "Product not available");
        require(product.stock >= _quantity, "Insufficient stock");
        require(_quantity > 0, "Quantity must be greater than 0");

        // Check if token is accepted for this product
        bool tokenAccepted = false;
        for (uint256 i = 0; i < product.acceptedTokens.length; i++) {
            if (product.acceptedTokens[i] == _paymentToken) {
                tokenAccepted = true;
                break;
            }
        }
        require(tokenAccepted, "Payment token not accepted");

        uint256 totalAmount = product.price * _quantity;
        uint256 platformFee = (totalAmount * platformFeePercentage) / 10000;
        uint256 merchantAmount = totalAmount - platformFee;

        // Transfer payment from customer
        require(
            IERC20(_paymentToken).transferFrom(msg.sender, address(this), totalAmount),
            "Payment transfer failed"
        );

        // Transfer to merchant
        require(
            IERC20(_paymentToken).transfer(product.merchant, merchantAmount),
            "Merchant payment failed"
        );

        // Store platform fee
        platformFees[_paymentToken] += platformFee;

        // Update product stock and merchant stats
        productCatalog.reserveStock(_productId, _quantity);
        merchantRegistry.updateMerchantStats(product.merchant, totalAmount, true);

        emit ProductPurchased(_productId, msg.sender, 0, false); // 0 planId for direct purchase
    }

    function purchaseProductWithInstallments(
        uint256 _productId,
        address _paymentToken,
        uint256 _quantity,
        uint256 _downPayment,
        uint256 _numberOfInstallments
    ) external whenNotPaused nonReentrant returns (uint256) {
        IProductCatalog.Product memory product = productCatalog.getProduct(_productId);
        require(product.isAvailable, "Product not available");
        require(product.allowInstallments, "Installments not allowed for this product");
        require(product.stock >= _quantity, "Insufficient stock");
        require(_quantity > 0, "Quantity must be greater than 0");
        require(_numberOfInstallments >= 2 && _numberOfInstallments <= product.maxInstallments, "Invalid installment count");

        // Check if token is accepted for this product
        bool tokenAccepted = false;
        for (uint256 i = 0; i < product.acceptedTokens.length; i++) {
            if (product.acceptedTokens[i] == _paymentToken) {
                tokenAccepted = true;
                break;
            }
        }
        require(tokenAccepted, "Payment token not accepted");

        uint256 totalAmount = product.price * _quantity;
        uint256 minDownPayment = (totalAmount * product.minDownPaymentRate) / 10000;
        require(_downPayment >= minDownPayment, "Down payment too low");
        require(_downPayment < totalAmount, "Down payment exceeds total");

        // Check customer eligibility
        IInstallmentManager.CustomerEligibility memory eligibility = installmentManager.checkCustomerEligibility(msg.sender, totalAmount);
        require(eligibility.isEligible, eligibility.reason);

        // Reserve the stock
        productCatalog.reserveStock(_productId, _quantity);

        // Create installment plan
        string memory productDescription = string(abi.encodePacked(
            _toString(_quantity), "x ", product.name
        ));

        uint256 planId = installmentManager.createInstallmentPlan(
            msg.sender,
            product.merchant,
            productDescription,
            _paymentToken,
            totalAmount,
            _downPayment,
            _numberOfInstallments,
            product.installmentFrequency,
            100 // Default 1% late penalty
        );

        emit ProductPurchased(_productId, msg.sender, planId, true);
        return planId;
    }

    function makeInstallmentPayment(uint256 _planId) external whenNotPaused {
        installmentManager.makePayment(_planId);
    }

    function checkCustomerEligibility(address _customer, uint256 _amount)
        external
        view
        returns (IInstallmentManager.CustomerEligibility memory)
    {
        return installmentManager.checkCustomerEligibility(_customer, _amount);
    }

    // View functions
    function getAllProducts() external view returns (IProductCatalog.ProductSummary[] memory) {
        return productCatalog.getAllProducts();
    }

    function getProductsByCategory(string memory _category) external view returns (IProductCatalog.ProductSummary[] memory) {
        return productCatalog.getProductsByCategory(_category);
    }

    function getMerchantProducts(address _merchant) external view returns (IProductCatalog.ProductSummary[] memory) {
        return productCatalog.getMerchantProducts(_merchant);
    }

    function getProduct(uint256 _productId) external view returns (IProductCatalog.ProductSummary memory) {
        return productCatalog.getProductSummary(_productId);
    }

    function searchProducts(string memory _searchTerm) external view returns (IProductCatalog.ProductSummary[] memory) {
        return productCatalog.searchProducts(_searchTerm);
    }

    function getInstallmentPlanSummary(uint256 _planId) external view returns (IInstallmentManager.InstallmentSummary memory) {
        return installmentManager.getInstallmentPlanSummary(_planId);
    }

    function getCustomerPlans(address _customer) external view returns (uint256[] memory) {
        return installmentManager.getCustomerPlans(_customer);
    }

    function getMerchantPlans(address _merchant) external view returns (uint256[] memory) {
        return installmentManager.getMerchantPlans(_merchant);
    }

    function getMerchantInfo(address _merchant) external view returns (IMerchantRegistry.Merchant memory) {
        return merchantRegistry.getMerchantInfo(_merchant);
    }

    function getAllMerchants() external view returns (address[] memory) {
        return merchantRegistry.getAllMerchants();
    }

    // Helper function
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
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

    // Admin functions
    function setPlatformFee(uint256 _feePercentage) external onlyOwner {
        require(_feePercentage <= 500, "Fee too high"); // Max 5%
        platformFeePercentage = _feePercentage;
    }

    function withdrawPlatformFees(address _token) external onlyOwner {
        uint256 amount = platformFees[_token];
        require(amount > 0, "No fees to withdraw");

        platformFees[_token] = 0;
        require(IERC20(_token).transfer(owner(), amount), "Withdrawal failed");

        emit PlatformFeesWithdrawn(_token, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Emergency functions
    function emergencyWithdraw(address _token) external onlyOwner {
        uint256 balance = IERC20(_token).balanceOf(address(this));
        require(balance > 0, "No balance to withdraw");
        require(IERC20(_token).transfer(owner(), balance), "Emergency withdrawal failed");
    }
}
