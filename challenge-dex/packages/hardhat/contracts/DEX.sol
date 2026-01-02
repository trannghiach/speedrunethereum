// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DEX Template
 * @author stevepham.eth and m00npapi.eth
 * @notice Empty DEX.sol that just outlines what features could be part of the challenge (up to you!)
 * @dev We want to create an automatic market where our contract will hold reserves of both ETH and 🎈 Balloons. These reserves will provide liquidity that allows anyone to swap between the assets.
 * NOTE: functions outlined here are what work with the front end of this challenge. Also return variable names need to be specified exactly may be referenced (It may be helpful to cross reference with front-end code function calls).
 */
contract DEX {
    /* ========== GLOBAL VARIABLES ========== */

    IERC20 token; //instantiates the imported contract
    //BỔ SUNG: Biến để theo dõi tổng thanh khoản và thanh khoản của từng user
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;

    /* ========== EVENTS ========== */

    /**
     * @notice Emitted when ethToToken() swap transacted
     */
    event EthToTokenSwap(address swapper, uint256 tokenOutput, uint256 ethInput);

    /**
     * @notice Emitted when tokenToEth() swap transacted
     */
    event TokenToEthSwap(address swapper, uint256 tokensInput, uint256 ethOutput);

    /**
     * @notice Emitted when liquidity provided to DEX and mints LPTs.
     */
    event LiquidityProvided(address liquidityProvider, uint256 liquidityMinted, uint256 ethInput, uint256 tokensInput);

    /**
     * @notice Emitted when liquidity removed from DEX and decreases LPT count within DEX.
     */
    event LiquidityRemoved(
        address liquidityRemover,
        uint256 liquidityWithdrawn,
        uint256 tokensOutput,
        uint256 ethOutput
    );

    /* ========== CONSTRUCTOR ========== */

    constructor(address tokenAddr) {
        token = IERC20(tokenAddr); //specifies the token address that will hook into the interface and be used through the variable 'token'
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    // --- CHECKPOINT 2: INIT ---
    function init(uint256 tokens) public payable returns (uint256) {
        require(totalLiquidity == 0, "DEX: init - already has liquidity");
        
        //Tổng thanh khoản ban đầu = số ETH nạp vào
        totalLiquidity = address(this).balance;
        //Ghi nhận công trạng cho người khởi tạo (msg.sender)
        liquidity[msg.sender] = totalLiquidity;
        
        //Chuyển Tokens từ ví người tạo vào DEX
        require(token.transferFrom(msg.sender, address(this), tokens), "DEX: init - transfer failed");
        
        return totalLiquidity;
    }

    // --- CHECKPOINT 2: PRICE (Công thức x*y=k) ---
    function price(uint256 xInput, uint256 xReserves, uint256 yReserves) public pure returns (uint256 yOutput) {
        //Phí 0.3% -> Input * 997 / 1000
        uint256 input_amount_with_fee = xInput * 997;
        uint256 numerator = input_amount_with_fee * yReserves;
        uint256 denominator = (xReserves * 1000) + input_amount_with_fee;
        
        return numerator / denominator;
    }

    // --- CHECKPOINT 2: GET LIQUIDITY ---
    function getLiquidity(address lp) public view returns (uint256) {
        return liquidity[lp];
    }


    //@notice sends Ether to DEX in exchange for $BAL
    function ethToToken() public payable returns (uint256 tokenOutput) {
        require(msg.value > 0, "Cannot swap 0 ETH");

        uint256 ethReserve = address(this).balance - msg.value; // Trừ msg.value để lấy số dư cũ
        uint256 tokenReserve = token.balanceOf(address(this));

        //Tính toán lượng Token nhận được
        tokenOutput = price(msg.value, ethReserve, tokenReserve);

        //Chuyển Token cho người mua
        require(token.transfer(msg.sender, tokenOutput), "ethToToken: Failed to transfer tokens");

        emit EthToTokenSwap(msg.sender, tokenOutput, msg.value);
        
        return tokenOutput;
    }

    //@notice sends $BAL tokens to DEX in exchange for Ether
    function tokenToEth(uint256 tokenInput) public returns (uint256 ethOutput) {
        require(tokenInput > 0, "Cannot swap 0 tokens");

        uint256 tokenReserve = token.balanceOf(address(this));
        uint256 ethReserve = address(this).balance;

        //Tính toán lượng ETH nhận được
        ethOutput = price(tokenInput, tokenReserve, ethReserve);

        //Kéo Token từ người bán về DEX (Cần Approve trước!)
        require(token.transferFrom(msg.sender, address(this), tokenInput), "tokenToEth: Failed to transfer tokens");

        //Trả ETH cho người bán
        (bool sent, ) = msg.sender.call{value: ethOutput}("");
        require(sent, "tokenToEth: Failed to send ETH");

        emit TokenToEthSwap(msg.sender, tokenInput, ethOutput);

        return ethOutput;
    }

    // --- CHECKPOINT 5: DEPOSIT ---
    function deposit() public payable returns (uint256 tokensDeposited) {
        require(msg.value > 0, "Must send value when depositing");
        
        //Lấy dữ liệu dự trữ (Trừ msg.value để lấy trạng thái cũ)
        uint256 ethReserve = address(this).balance - msg.value;
        uint256 tokenReserve = token.balanceOf(address(this));
        
        //Tính số Token user cần nạp theo tỷ lệ +1 tránh / 0 || làm tròn quá nhỏ
        uint256 tokenDeposit = (msg.value * tokenReserve / ethReserve) + 1;

        //ính số LP Token sẽ in ra
        uint256 liquidityMinted = msg.value * totalLiquidity / ethReserve;
        
        //Cập nhật State
        liquidity[msg.sender] += liquidityMinted;
        totalLiquidity += liquidityMinted;

        //Kéo Token về (Cần Approve trước)
        require(token.transferFrom(msg.sender, address(this), tokenDeposit), "Deposit failed");
        
        emit LiquidityProvided(msg.sender, liquidityMinted, msg.value, tokenDeposit);
        return tokenDeposit;
    }

    // --- CHECKPOINT 5: WITHDRAW ---
    function withdraw(uint256 amount) public returns (uint256 ethAmount, uint256 tokenAmount) {
        require(liquidity[msg.sender] >= amount, "Not enough liquidity");
        
        uint256 ethReserve = address(this).balance;
        uint256 tokenReserve = token.balanceOf(address(this));
        
        //Tính toán lượng tiền trả về dựa trên % sở hữu
        uint256 ethWithdrawn = (amount * ethReserve) / totalLiquidity;
        uint256 tokenOutput = (amount * tokenReserve) / totalLiquidity;
        
        //Cập nhật State (Burn LP Token)
        liquidity[msg.sender] -= amount;
        totalLiquidity -= amount;
        
        //Trả tiền
        (bool sent, ) = payable(msg.sender).call{value: ethWithdrawn}("");
        require(sent, "Withdraw ETH failed");
        require(token.transfer(msg.sender, tokenOutput), "Withdraw Token failed");
        
        emit LiquidityRemoved(msg.sender, amount, tokenOutput, ethWithdrawn);
        return (ethWithdrawn, tokenOutput);
    }
}
