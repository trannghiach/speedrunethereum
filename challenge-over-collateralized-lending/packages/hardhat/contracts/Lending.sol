// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./Corn.sol";
import "./CornDEX.sol";

error Lending__InvalidAmount();
error Lending__TransferFailed();
error Lending__UnsafePositionRatio();
error Lending__BorrowingFailed();
error Lending__RepayingFailed();
error Lending__PositionSafe();
error Lending__NotLiquidatable();
error Lending__InsufficientLiquidatorCorn();

contract Lending is Ownable {
    uint256 private constant COLLATERAL_RATIO = 120; // 120% collateralization required
    uint256 private constant LIQUIDATOR_REWARD = 10; // 10% reward for liquidators

    Corn private i_corn;
    CornDEX private i_cornDEX;

    mapping(address => uint256) public s_userCollateral; // User's collateral balance
    mapping(address => uint256) public s_userBorrowed; // User's borrowed corn balance

    event CollateralAdded(address indexed user, uint256 indexed amount, uint256 price);
    event CollateralWithdrawn(address indexed user, uint256 indexed amount, uint256 price);
    event AssetBorrowed(address indexed user, uint256 indexed amount, uint256 price);
    event AssetRepaid(address indexed user, uint256 indexed amount, uint256 price);
    event Liquidation(
        address indexed user,
        address indexed liquidator,
        uint256 amountForLiquidator,
        uint256 liquidatedUserDebt,
        uint256 price
    );

    constructor(address _cornDEX, address _corn) Ownable(msg.sender) {
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        i_corn.approve(address(this), type(uint256).max);
    }

    /**
     * @notice Allows users to add collateral to their account
     * @dev Nhận ETH và ghi nhận vào mapping s_userCollateral
     */
    function addCollateral() public payable {
        //Kiểm tra: Không được nạp 0 đồng
        if (msg.value == 0) {
            revert Lending__InvalidAmount();
        }

        //Cập nhật số dư thế chấp của user
        s_userCollateral[msg.sender] += msg.value;

        //Thông báo (kèm theo giá hiện tại từ DEX để Frontend hiển thị)
        emit CollateralAdded(msg.sender, msg.value, i_cornDEX.currentPrice());
    }

    /**
     * @notice Allows users to withdraw collateral
     * @param amount Số lượng ETH muốn rút (đơn vị Wei)
     */
    function withdrawCollateral(uint256 amount) public {
        //Kiểm tra: Số rút phải > 0 và User phải có đủ tiền trong tài khoản
        if (amount == 0 || s_userCollateral[msg.sender] < amount) {
            revert Lending__InvalidAmount();
        }

        //Trừ tiền trong sổ cái trước (Cập nhật State - Chống Reentrancy)
        s_userCollateral[msg.sender] -= amount;

        if (s_userBorrowed[msg.sender] > 0) {
            _validatePosition(msg.sender);
        }

        //Thực hiện chuyển ETH trả lại user
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert Lending__TransferFailed();
        }

        //Emit event
        emit CollateralWithdrawn(msg.sender, amount, i_cornDEX.currentPrice());
    }

    /**
     * @notice Calculates the total collateral value for a user based on their collateral balance
     * @param user The address of the user to calculate the collateral value for
     * @return uint256 The collateral value in CORN
     */
    function calculateCollateralValue(address user) public view returns (uint256) {
        uint256 totalCollateral = s_userCollateral[user];
        uint256 price = i_cornDEX.currentPrice(); // Giá 1 ETH = bao nhiêu Corn
        return (totalCollateral * price) / 1e18;
    }

   /**
     * @notice Calculates the position ratio for a user
     * @return uint256 The position ratio (scaled by 1e18)
     */
    function _calculatePositionRatio(address user) internal view returns (uint256) {
        uint borrowedAmount = s_userBorrowed[user];
        uint collateralValue = calculateCollateralValue(user);
        
        // Nếu chưa vay đồng nào -> An toàn tuyệt đối (trả về max uint)
        if (borrowedAmount == 0) return type(uint256).max;
        
        // Công thức: (Tài sản * 1e18) / Nợ
        return (collateralValue * 1e18) / borrowedAmount;
    }

    /**
     * @notice Checks if a user's position can be liquidated
     * @return bool True if position is unsafe (< 120%)
     */
    function isLiquidatable(address user) public view returns (bool) {
        uint256 positionRatio = _calculatePositionRatio(user);
        
        // Kiểm tra: (Ratio * 100) < (120 * 1e18)
        // Ví dụ: Ratio là 1.1 (110%) -> 1.1 * 1e18 * 100 = 110 * 1e18 < 120 * 1e18 -> True (Bị thanh lý)
        return (positionRatio * 100) < COLLATERAL_RATIO * 1e18;
    }

    /**
     * @notice Reverts if a user's position is unsafe
     */
    function _validatePosition(address user) internal view {
        if (isLiquidatable(user)) {
            revert Lending__UnsafePositionRatio();
        }
    }

    // --- CHECKPOINT 4: BORROW ---
    function borrowCorn(uint256 borrowAmount) public {
        // 1. Kiểm tra đầu vào
        if (borrowAmount == 0) {
            revert Lending__InvalidAmount();
        }
        
        // 2. Tăng nợ (Update State trước khi Transfer để tránh Reentrancy)
        s_userBorrowed[msg.sender] += borrowAmount;
        
        // 3. Kiểm tra an toàn vốn (Quan trọng nhất)
        // Nếu vay xong mà tỷ lệ < 120% -> Revert ngay lập tức
        _validatePosition(msg.sender);
        
        // 4. Chuyển token CORN cho user
        bool success = i_corn.transfer(msg.sender, borrowAmount);
        if (!success) {
            revert Lending__BorrowingFailed();
        }
        
        emit AssetBorrowed(msg.sender, borrowAmount, i_cornDEX.currentPrice());
    }

    // --- CHECKPOINT 4: REPAY ---
    function repayCorn(uint256 repayAmount) public {
        // 1. Kiểm tra: Phải trả > 0 và không trả quá số nợ
        if (repayAmount == 0 || repayAmount > s_userBorrowed[msg.sender]) {
            revert Lending__InvalidAmount();
        }
        
        // 2. Giảm nợ
        s_userBorrowed[msg.sender] -= repayAmount;
        
        // 3. Thu hồi token (User -> Contract)
        // Lưu ý: User phải APPROVE cho Lending contract trước thì lệnh này mới chạy được
        bool success = i_corn.transferFrom(msg.sender, address(this), repayAmount);
        if (!success) {
            revert Lending__RepayingFailed();
        }
        
        emit AssetRepaid(msg.sender, repayAmount, i_cornDEX.currentPrice());
    }

    // --- CHECKPOINT 5: LIQUIDATION ---
    /**
     * @notice Allows liquidators to liquidate unsafe positions
     * @param user The address of the user to liquidate
     */
    function liquidate(address user) public {
        if (!isLiquidatable(user)) {
            revert Lending__NotLiquidatable(); 
        }

        uint256 userDebt = s_userBorrowed[user]; // Số nợ của nạn nhân

        //Kiểm tra "sát thủ" (Liquidator) có đủ tiền trả nợ thay không?
        if (i_corn.balanceOf(msg.sender) < userDebt) {
            revert Lending__InsufficientLiquidatorCorn();
        }

        uint256 userCollateral = s_userCollateral[user]; // Tổng ETH thế chấp của nạn nhân
        uint256 collateralValue = calculateCollateralValue(user); // Giá trị ETH đó quy ra CORN

        //Thu nợ: Kéo CORN từ ví Liquidator về Contract
        i_corn.transferFrom(msg.sender, address(this), userDebt);

        //Xóa nợ cho nạn nhân (Nạn nhân giữ luôn số CORN đã vay trước đó)
        s_userBorrowed[user] = 0;

        // Quy đổi số nợ (CORN) sang ETH tương ứng
        uint256 collateralPurchased = (userDebt * userCollateral) / collateralValue;
        
        // Tính thưởng 10%
        uint256 liquidatorReward = (collateralPurchased * LIQUIDATOR_REWARD) / 100;
        
        // Tổng ETH Liquidator nhận được
        uint256 amountForLiquidator = collateralPurchased + liquidatorReward;

        // Đảm bảo không lấy quá số tiền nạn nhân có (tránh lỗi underflow)
        amountForLiquidator = amountForLiquidator > userCollateral ? userCollateral : amountForLiquidator;

        // Trừ tiền trong sổ cái của nạn nhân
        s_userCollateral[user] = userCollateral - amountForLiquidator;

        // 6. Trả ETH (Gốc + Thưởng) cho Liquidator
        (bool success,) = payable(msg.sender).call{ value: amountForLiquidator }("");
        if (!success) {
            revert Lending__TransferFailed();
        }

        emit Liquidation(user, msg.sender, amountForLiquidator, userDebt, i_cornDEX.currentPrice());
    }
}
