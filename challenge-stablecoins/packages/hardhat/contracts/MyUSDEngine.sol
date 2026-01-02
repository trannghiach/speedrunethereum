// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./MyUSD.sol";
import "./Oracle.sol";
import "./MyUSDStaking.sol";

error Engine__InvalidAmount();
error Engine__UnsafePositionRatio();
error Engine__NotLiquidatable();
error Engine__InvalidBorrowRate();
error Engine__NotRateController();
error Engine__InsufficientCollateral();
error Engine__TransferFailed();

contract MyUSDEngine is Ownable {
    uint256 private constant COLLATERAL_RATIO = 150; // 150% collateralization required
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10% reward for liquidators
    uint256 private constant SECONDS_PER_YEAR = 365 days;
    uint256 private constant PRECISION = 1e18;

    MyUSD private i_myUSD;
    Oracle private i_oracle;
    MyUSDStaking private i_staking;
    address private i_rateController;

    uint256 public borrowRate; // Annual interest rate for borrowers in basis points (1% = 100)

    // Total debt shares in the pool
    uint256 public totalDebtShares;

    // Exchange rate between debt shares and MyUSD (1e18 precision)
    uint256 public debtExchangeRate;
    uint256 public lastUpdateTime;

    mapping(address => uint256) public s_userCollateral;
    mapping(address => uint256) public s_userDebtShares;

    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    event CollateralWithdrawn(address indexed withdrawer, uint256 indexed amount, uint256 price);
    event BorrowRateUpdated(uint256 newRate);
    event DebtSharesMinted(address indexed user, uint256 amount, uint256 shares);
    event DebtSharesBurned(address indexed user, uint256 amount, uint256 shares);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    modifier onlyRateController() {
        if (msg.sender != i_rateController) revert Engine__NotRateController();
        _;
    }

    constructor(
        address _oracle,
        address _myUSDAddress,
        address _stakingAddress,
        address _rateController
    ) Ownable(msg.sender) {
        i_oracle = Oracle(_oracle);
        i_myUSD = MyUSD(_myUSDAddress);
        i_staking = MyUSDStaking(_stakingAddress);
        i_rateController = _rateController;
        lastUpdateTime = block.timestamp;
        debtExchangeRate = PRECISION; // 1:1 initially
    }

    // Checkpoint 2: Depositing Collateral & Understanding Value
    function addCollateral() public payable {
        if (msg.value == 0) {
            revert Engine__InvalidAmount();
        }

        s_userCollateral[msg.sender] += msg.value;

        uint256 price = i_oracle.getETHMyUSDPrice(); 
        
        emit CollateralAdded(msg.sender, msg.value, price);
    }

    function calculateCollateralValue(address user) public view returns (uint256) {
        uint256 ethAmount = s_userCollateral[user];
        if (ethAmount == 0) return 0;

        uint256 price = i_oracle.getETHMyUSDPrice();

        // (Số lượng ETH * Giá) / 1e18
        return (ethAmount * price) / PRECISION;
    }

    // Checkpoint 3: Interest Calculation System
    function _getCurrentExchangeRate() internal view returns (uint256) {
        // Nếu chưa có thời gian trôi qua hoặc chưa có nợ, tỷ giá không đổi
        if (lastUpdateTime == 0 || totalDebtShares == 0) {
            return debtExchangeRate;
        }

        uint256 timeElapsed = block.timestamp - lastUpdateTime;
        
        // borrowRate đơn vị là basis points (1% = 100) -> Phải chia cho 10000 (100 * 100%)
        // Công thức: (Tỷ Giá * Lãi Suất * Thời Gian) / (Năm * 10000)
        uint256 interestIncrease = (debtExchangeRate * borrowRate * timeElapsed) / (SECONDS_PER_YEAR * 10000);

        return debtExchangeRate + interestIncrease;
    }

    function _accrueInterest() internal {
        // Nếu chưa có nợ thì chỉ update thời gian, không cần tính lãi
        if (totalDebtShares == 0) {
            lastUpdateTime = block.timestamp;
            return;
        }

        // Cập nhật State
        debtExchangeRate = _getCurrentExchangeRate();
        lastUpdateTime = block.timestamp;
        
        // TODO: emit
    }

    function _getMyUSDToShares(uint256 amount) internal view returns (uint256) {
        uint256 currentExchangeRate = _getCurrentExchangeRate();
        
        // Công thức: Shares = (Amount * 1e18) / ExchangeRate
        return (amount * PRECISION) / currentExchangeRate;
    }

    // Checkpoint 4: Minting MyUSD & Position Health
    function getCurrentDebtValue(address user) public view returns (uint256) {
        if (s_userDebtShares[user] == 0) return 0;
        
        // Lấy tỷ giá mới nhất (đã bao gồm lãi tính đến giây hiện tại)
        uint256 currentExchangeRate = _getCurrentExchangeRate();
        
        // Công thức: (Shares * Rate) / Precision
        return (s_userDebtShares[user] * currentExchangeRate) / PRECISION;
    }

    function calculatePositionRatio(address user) public view returns (uint256) {
        uint256 debtValue = getCurrentDebtValue(user);
        
        // Nếu không có nợ -> An toàn tuyệt đối (Max Int)
        if (debtValue == 0) return type(uint256).max;
        
        uint256 collateralValue = calculateCollateralValue(user);
        
        // (Collateral * 1e18) / Debt
        return (collateralValue * PRECISION) / debtValue;
    }

    function _validatePosition(address user) internal view {
        uint256 positionRatio = calculatePositionRatio(user);
        
        // So sánh: (Ratio * 100) < (150 * 1e18)
        if ((positionRatio * 100) < COLLATERAL_RATIO * PRECISION) {
            revert Engine__UnsafePositionRatio();
        }
    }

    function mintMyUSD(uint256 mintAmount) public {
        if (mintAmount == 0) revert Engine__InvalidAmount();
        
        // 1. Quy đổi số tiền muốn vay ra số Cổ phần nợ (Shares)
        uint256 shares = _getMyUSDToShares(mintAmount);
        
        // 2. Cập nhật sổ cái (User nợ thêm share, Tổng nợ hệ thống tăng thêm share)
        s_userDebtShares[msg.sender] += shares;
        totalDebtShares += shares;
        
        // 3. Kiểm tra an toàn: Vay xong có bị vi phạm tỷ lệ 150% không?
        _validatePosition(msg.sender);
        
        // 4. Nếu an toàn -> Gọi sang Token Contract để in tiền vào ví user
        i_myUSD.mintTo(msg.sender, mintAmount);
        
        emit DebtSharesMinted(msg.sender, mintAmount, shares);
    }

    // Checkpoint 9: The Other Side: Savings Rate & Market Dynamics
    function setBorrowRate(uint256 newRate) external onlyRateController {
        // CHECK MỚI: Lãi cho vay phải >= Lãi tiết kiệm
        // Nếu thu 5% mà trả lãi 10% thì hệ thống lỗ vốn -> Sập
        if (newRate < i_staking.savingsRate()) {
            revert Engine__InvalidBorrowRate();
        }

        _accrueInterest();
        borrowRate = newRate;
        emit BorrowRateUpdated(newRate);
    }

    // Checkpoint 6: Repaying Debt & Withdrawing Collateral
    function repayUpTo(uint256 amount) public {
        // 1. Quy đổi số tiền muốn trả ra Cổ phần (Shares)
        uint256 amountInShares = _getMyUSDToShares(amount);
        
        // 2. Logic "Trả Hết": 
        // Nếu user muốn trả nhiều hơn số nợ thực tế -> Chỉ thu đúng số nợ thực tế
        if (amountInShares > s_userDebtShares[msg.sender]) {
            amountInShares = s_userDebtShares[msg.sender];
            // Tính lại số MyUSD chính xác cần trả
            amount = getCurrentDebtValue(msg.sender);
        }

        // 3. Kiểm tra số dư ví User
        if (amount == 0 || i_myUSD.balanceOf(msg.sender) < amount) {
            revert MyUSD__InsufficientBalance();
        }

        // 4. Kiểm tra User đã Approve cho Engine chưa?
        // (Engine cần quyền burn token từ ví user)
        if (i_myUSD.allowance(msg.sender, address(this)) < amount) {
            revert MyUSD__InsufficientAllowance();
        }

        // 5. Cập nhật sổ cái (Giảm nợ)
        s_userDebtShares[msg.sender] -= amountInShares;
        totalDebtShares -= amountInShares;

        // 6. Đốt token từ ví user
        i_myUSD.burnFrom(msg.sender, amount);

        emit DebtSharesBurned(msg.sender, amount, amountInShares);
    }

    function withdrawCollateral(uint256 amount) external {
        if (amount == 0) revert Engine__InvalidAmount();
        if (s_userCollateral[msg.sender] < amount) revert Engine__InsufficientCollateral();
        
        // 1. Trừ tiền trước (Optimistic)
        uint256 newCollateral = s_userCollateral[msg.sender] - amount;
        s_userCollateral[msg.sender] = newCollateral;

        // 2. CHECK AN TOÀN: Rút xong có bị vỡ nợ không?
        // Chỉ cần check nếu user đang có nợ
        if (s_userDebtShares[msg.sender] > 0) {
            _validatePosition(msg.sender); 
            // Nếu không an toàn, hàm _validatePosition sẽ Revert -> Hoàn tác toàn bộ
        }

        // 3. Chuyển ETH về ví
        payable(msg.sender).transfer(amount);

        emit CollateralWithdrawn(msg.sender, amount, i_oracle.getETHMyUSDPrice());
    }

    // Checkpoint 7: Liquidation - Enforcing System Stability
    function isLiquidatable(address user) public view returns (bool) {
        uint256 positionRatio = calculatePositionRatio(user);
        // Kiểm tra: (Ratio * 100) < (150 * 1e18)
        return (positionRatio * 100) < COLLATERAL_RATIO * PRECISION;
    }

    function liquidate(address user) external {
        // 1. Cập nhật lãi suất mới nhất trước khi tính toán
        _accrueInterest();

        // 2. Kiểm tra nạn nhân có đáng bị thanh lý không?
        if (!isLiquidatable(user)) {
            revert Engine__NotLiquidatable();
        }

        // 3. Lấy thông tin nợ và tài sản
        uint256 userDebtValue = getCurrentDebtValue(user);
        uint256 userCollateral = s_userCollateral[user];
        uint256 collateralValue = calculateCollateralValue(user);

        // 4. Kiểm tra Liquidator (Sát thủ) có đủ tiền trả nợ thay không?
        if (i_myUSD.balanceOf(msg.sender) < userDebtValue) {
            revert MyUSD__InsufficientBalance();
        }

        // 5. Kiểm tra quyền Approve
        if (i_myUSD.allowance(msg.sender, address(this)) < userDebtValue) {
            revert MyUSD__InsufficientAllowance();
        }

        // 6. Đốt MyUSD của Liquidator
        i_myUSD.burnFrom(msg.sender, userDebtValue);

        // 7. Xóa sổ nợ cho nạn nhân
        totalDebtShares -= s_userDebtShares[user];
        s_userDebtShares[user] = 0;

        // 8. Tính toán phần thưởng ETH cho Liquidator
        // ETH cần để trả nợ = (Nợ * Tổng ETH) / Tổng giá trị USD của ETH
        uint256 collateralToCoverDebt = (userDebtValue * userCollateral) / collateralValue;
        // Thưởng 10%
        uint256 rewardAmount = (collateralToCoverDebt * LIQUIDATOR_REWARD) / 100;
        uint256 amountForLiquidator = collateralToCoverDebt + rewardAmount;
        
        // Cap (Giới hạn): Không được lấy quá số ETH nạn nhân đang có
        if (amountForLiquidator > userCollateral) {
            amountForLiquidator = userCollateral;
        }

        // 9. Trừ ETH của nạn nhân và trả cho Liquidator
        s_userCollateral[user] = userCollateral - amountForLiquidator;

        (bool sent, ) = payable(msg.sender).call{ value: amountForLiquidator }("");
        if (!sent) revert Engine__TransferFailed();

        // 10. Emit Event
        emit Liquidation(user, msg.sender, amountForLiquidator, userDebtValue, i_oracle.getETHUSDPrice());
    }
}
