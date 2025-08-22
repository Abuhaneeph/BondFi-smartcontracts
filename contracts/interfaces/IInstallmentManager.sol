// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IInstallmentManager {
    struct InstallmentPlan {
        uint256 planId;
        address customer;
        string customerName;
        address merchant;
        string merchantName;
        string productDescription;
        address paymentToken;
        uint256 totalAmount;
        uint256 downPayment;
        uint256 installmentAmount;
        uint256 numberOfInstallments;
        uint256 installmentFrequency;
        uint256 currentInstallment;
        uint256 nextPaymentDue;
        uint256 createdAt;
        bool isActive;
        bool isCompleted;
        bool hasDefaulted;
        uint256 latePenaltyRate;
        uint256 totalPaid;
    }

    struct InstallmentSummary {
        uint256 planId;
        address customer;
        string customerName;
        address merchant;
        string merchantName;
        string productDescription;
        address paymentToken;
        string tokenName;
        uint256 totalAmount;
        uint256 downPayment;
        uint256 installmentAmount;
        uint256 numberOfInstallments;
        uint256 currentInstallment;
        uint256 nextPaymentDue;
        bool isActive;
        bool isCompleted;
        bool hasDefaulted;
        uint256 totalPaid;
        uint256 remainingAmount;
        uint256 daysPastDue;
    }

    struct CustomerEligibility {
        bool isEligible;
        uint256 maxInstallmentAmount;
        uint256 trustScore;
        string reason;
        uint256 recommendedDownPayment;
    }

    event InstallmentPlanCreated(uint256 indexed planId, address indexed customer, address indexed merchant, uint256 productId, uint256 totalAmount, uint256 installments);
    event InstallmentPaymentMade(uint256 indexed planId, address indexed customer, uint256 installmentNumber, uint256 amount, uint256 penalty);
    event InstallmentPlanCompleted(uint256 indexed planId, address indexed customer, address indexed merchant);
    event DefaultDetected(uint256 indexed planId, address indexed customer, uint256 daysPastDue);

    function createInstallmentPlan(
        address _customer,
        address _merchant,
        string memory _productDescription,
        address _paymentToken,
        uint256 _totalAmount,
        uint256 _downPayment,
        uint256 _numberOfInstallments,
        uint256 _installmentFrequency,
        uint256 _latePenaltyRate
    ) external returns (uint256);

    function makePayment(uint256 _planId) external;
    function checkCustomerEligibility(address _customer, uint256 _amount) external view returns (CustomerEligibility memory);
    function getInstallmentPlanSummary(uint256 _planId) external view returns (InstallmentSummary memory);
    function getCustomerPlans(address _customer) external view returns (uint256[] memory);
    function getMerchantPlans(address _merchant) external view returns (uint256[] memory);
    function markAsDefaulted(uint256 _planId) external;
}
