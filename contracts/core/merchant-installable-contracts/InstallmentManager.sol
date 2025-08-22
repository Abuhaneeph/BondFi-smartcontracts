// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "../../interfaces/IAjoEsusuSavings.sol";
import "../../interfaces/IInstallmentManager.sol";
import "../../interfaces/IMerchantRegistry.sol";



contract InstallmentManager is IInstallmentManager, ReentrancyGuard, Ownable, Pausable {
    IAjoEsusuSavings public immutable ajoContract;
    IMerchantRegistry public immutable merchantRegistry;
    
    uint256 public nextPlanId = 1;
    uint256 public constant MIN_TRUST_SCORE = 60;
    uint256 public constant MIN_INSTALLMENT_FREQUENCY = 86400; // 1 day
    uint256 public constant MAX_INSTALLMENTS = 12;
    uint256 public constant MIN_DOWN_PAYMENT_RATE = 1000; // 10%

    mapping(uint256 => InstallmentPlan) public installmentPlans;
    mapping(uint256 => mapping(uint256 => bool)) public installmentPaid;
    mapping(uint256 => mapping(uint256 => uint256)) public installmentPaidAt;
    mapping(uint256 => mapping(uint256 => uint256)) public penaltiesAccrued;
    mapping(address => uint256[]) public customerPlans;
    mapping(address => uint256[]) public merchantPlans;
    mapping(address => bool) public authorizedContracts;

    modifier onlyAuthorized() {
        require(authorizedContracts[msg.sender] || msg.sender == owner(), "Not authorized");
        _;
    }

    modifier validPlanId(uint256 _planId) {
        require(_planId > 0 && _planId < nextPlanId, "Invalid plan ID");
        _;
    }

    modifier onlyPlanParticipant(uint256 _planId) {
        InstallmentPlan storage plan = installmentPlans[_planId];
        require(
            msg.sender == plan.customer || msg.sender == plan.merchant || msg.sender == owner(),
            "Not authorized"
        );
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
    ) external onlyAuthorized whenNotPaused nonReentrant returns (uint256) {
        require(merchantRegistry.merchantSupportsToken(_merchant, _paymentToken), "Token not accepted by merchant");
        require(_totalAmount > 0, "Invalid total amount");
        require(_numberOfInstallments >= 2 && _numberOfInstallments <= MAX_INSTALLMENTS, "Invalid installment count");
        require(_installmentFrequency >= MIN_INSTALLMENT_FREQUENCY, "Frequency too short");
        require(_downPayment >= (_totalAmount * MIN_DOWN_PAYMENT_RATE) / 10000, "Down payment too low");
        require(_downPayment < _totalAmount, "Down payment exceeds total");
        require(_latePenaltyRate <= 500, "Penalty rate too high"); // Max 5% per day
        require(bytes(_productDescription).length > 0, "Product description required");

        // Check customer eligibility
        CustomerEligibility memory eligibility = checkCustomerEligibility(_customer, _totalAmount);
        require(eligibility.isEligible, eligibility.reason);

        uint256 remainingAmount = _totalAmount - _downPayment;
        uint256 installmentAmount = remainingAmount / _numberOfInstallments;
        require(installmentAmount > 0, "Installment amount too small");

        uint256 planId = nextPlanId++;
        IMerchantRegistry.Merchant memory merchantInfo = merchantRegistry.getMerchantInfo(_merchant);

        installmentPlans[planId] = InstallmentPlan({
            planId: planId,
            customer: _customer,
            customerName: ajoContract.getUserName(_customer),
            merchant: _merchant,
            merchantName: merchantInfo.businessName,
            productDescription: _productDescription,
            paymentToken: _paymentToken,
            totalAmount: _totalAmount,
            downPayment: _downPayment,
            installmentAmount: installmentAmount,
            numberOfInstallments: _numberOfInstallments,
            installmentFrequency: _installmentFrequency,
            currentInstallment: 0,
            nextPaymentDue: block.timestamp, // Down payment due immediately
            createdAt: block.timestamp,
            isActive: true,
            isCompleted: false,
            hasDefaulted: false,
            latePenaltyRate: _latePenaltyRate,
            totalPaid: 0
        });

        customerPlans[_customer].push(planId);
        merchantPlans[_merchant].push(planId);

        emit InstallmentPlanCreated(planId, _customer, _merchant, 0, _totalAmount, _numberOfInstallments);

        return planId;
    }

    function makePayment(uint256 _planId) external validPlanId(_planId) whenNotPaused nonReentrant {
        InstallmentPlan storage plan = installmentPlans[_planId];
        require(msg.sender == plan.customer, "Only customer can make payments");
        require(plan.isActive && !plan.isCompleted && !plan.hasDefaulted, "Plan not active");
        require(plan.currentInstallment <= plan.numberOfInstallments, "All installments paid");

        uint256 paymentAmount;
        uint256 penalty = 0;

        if (plan.currentInstallment == 0) {
            // Down payment
            paymentAmount = plan.downPayment;
        } else {
            // Regular installment
            paymentAmount = plan.installmentAmount;

            // Calculate penalty if late
            if (block.timestamp > plan.nextPaymentDue) {
                uint256 daysLate = (block.timestamp - plan.nextPaymentDue) / 86400;
                penalty = (paymentAmount * plan.latePenaltyRate * daysLate) / 10000;
            }
        }

        uint256 totalPayment = paymentAmount + penalty;

        // Transfer payment from customer
        require(
            IERC20(plan.paymentToken).transferFrom(msg.sender, plan.merchant, totalPayment),
            "Payment transfer failed"
        );

        // Update plan state
        plan.currentInstallment++;
        plan.totalPaid += totalPayment;
        installmentPaid[_planId][plan.currentInstallment] = true;
        installmentPaidAt[_planId][plan.currentInstallment] = block.timestamp;

        if (penalty > 0) {
            penaltiesAccrued[_planId][plan.currentInstallment] = penalty;
        }

        // Set next payment due date
        if (plan.currentInstallment < plan.numberOfInstallments) {
            plan.nextPaymentDue = block.timestamp + plan.installmentFrequency;
        } else {
            // Plan completed
            plan.isCompleted = true;
            plan.isActive = false;

            // Update merchant stats
            merchantRegistry.updateMerchantStats(plan.merchant, plan.totalAmount, true);

            emit InstallmentPlanCompleted(_planId, plan.customer, plan.merchant);
        }

        emit InstallmentPaymentMade(_planId, msg.sender, plan.currentInstallment, paymentAmount, penalty);
    }

    function checkCustomerEligibility(address _customer, uint256 _amount) public view returns (CustomerEligibility memory) {
        if (!ajoContract.isUserRegistered(_customer)) {
            return CustomerEligibility({
                isEligible: false,
                maxInstallmentAmount: 0,
                trustScore: 0,
                reason: "Not registered in Ajo system",
                recommendedDownPayment: 0
            });
        }

        IAjoEsusuSavings.MemberInfo memory memberInfo = ajoContract.getMemberInfo(_customer);

        if (memberInfo.hasDefaulted) {
            return CustomerEligibility({
                isEligible: false,
                maxInstallmentAmount: 0,
                trustScore: memberInfo.reputationScore,
                reason: "Previous default history",
                recommendedDownPayment: 0
            });
        }

        if (memberInfo.reputationScore < MIN_TRUST_SCORE) {
            return CustomerEligibility({
                isEligible: false,
                maxInstallmentAmount: 0,
                trustScore: memberInfo.reputationScore,
                reason: "Insufficient trust score",
                recommendedDownPayment: 0
            });
        }

        // Calculate eligibility based on savings history
        uint256 maxAmount = _calculateMaxInstallmentAmount(memberInfo);
        uint256 downPaymentRate = _calculateDownPaymentRate(memberInfo);

        //bool isEligible = maxAmount >= _amount && memberInfo.completedGroups > 0;
       
    bool isEligible = memberInfo.reputationScore >= MIN_TRUST_SCORE && !memberInfo.hasDefaulted;

        return CustomerEligibility({
            isEligible: isEligible,
            maxInstallmentAmount: maxAmount,
            trustScore: memberInfo.reputationScore,
            reason: isEligible ? "Eligible" : "Amount exceeds maximum allowed",
            recommendedDownPayment: downPaymentRate
        });
    }

    function _calculateMaxInstallmentAmount(IAjoEsusuSavings.MemberInfo memory _memberInfo) internal pure returns (uint256) {
        // Base amount on total contributions and reputation
        uint256 baseAmount = _memberInfo.totalContributions;

        // Apply reputation multiplier
        uint256 reputationMultiplier = _memberInfo.reputationScore; // 60-100

        // Bonus for completed groups
        uint256 groupBonus = _memberInfo.completedGroups * 1000 * 10**18; // 1000 tokens per completed group

        return (baseAmount * reputationMultiplier / 100) + groupBonus;
    }

    function _calculateDownPaymentRate(IAjoEsusuSavings.MemberInfo memory _memberInfo) internal pure returns (uint256) {
        // Higher trust score = lower down payment required
        if (_memberInfo.reputationScore >= 90) return 1000; // 10%
        if (_memberInfo.reputationScore >= 80) return 1500; // 15%
        if (_memberInfo.reputationScore >= 70) return 2000; // 20%
        return 2500; // 25% for lower scores
    }

    function getInstallmentPlanSummary(uint256 _planId) external view validPlanId(_planId) returns (InstallmentSummary memory) {
        InstallmentPlan storage plan = installmentPlans[_planId];

        uint256 remainingAmount = plan.totalAmount - plan.totalPaid;
        uint256 daysPastDue = 0;

        if (plan.isActive && block.timestamp > plan.nextPaymentDue) {
            daysPastDue = (block.timestamp - plan.nextPaymentDue) / 86400;
        }

        return InstallmentSummary({
            planId: _planId,
            customer: plan.customer,
            customerName: plan.customerName,
            merchant: plan.merchant,
            merchantName: plan.merchantName,
            productDescription: plan.productDescription,
            paymentToken: plan.paymentToken,
            tokenName: ajoContract.tokenNames(plan.paymentToken),
            totalAmount: plan.totalAmount,
            downPayment: plan.downPayment,
            installmentAmount: plan.installmentAmount,
            numberOfInstallments: plan.numberOfInstallments,
            currentInstallment: plan.currentInstallment,
            nextPaymentDue: plan.nextPaymentDue,
            isActive: plan.isActive,
            isCompleted: plan.isCompleted,
            hasDefaulted: plan.hasDefaulted,
            totalPaid: plan.totalPaid,
            remainingAmount: remainingAmount,
            daysPastDue: daysPastDue
        });
    }

    function getCustomerPlans(address _customer) external view returns (uint256[] memory) {
        return customerPlans[_customer];
    }

    function getMerchantPlans(address _merchant) external view returns (uint256[] memory) {
        return merchantPlans[_merchant];
    }

    function markAsDefaulted(uint256 _planId) external validPlanId(_planId) {
        InstallmentPlan storage plan = installmentPlans[_planId];
        require(
            msg.sender == plan.merchant || msg.sender == owner(),
            "Not authorized"
        );
        require(plan.isActive && !plan.isCompleted && !plan.hasDefaulted, "Invalid plan state");

        // Check if payment is significantly overdue (more than 7 days)
        uint256 daysPastDue = (block.timestamp - plan.nextPaymentDue) / 86400;
        require(daysPastDue >= 7, "Not yet eligible for default");

        plan.hasDefaulted = true;
        plan.isActive = false;

        // Update merchant stats
        merchantRegistry.updateMerchantStats(plan.merchant, 0, false);

        emit DefaultDetected(_planId, plan.customer, daysPastDue);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
