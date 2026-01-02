pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "./YourToken.sol";
import "hardhat/console.sol";

contract Vendor is Ownable {
    //lưu địa chỉ YourToken
    YourToken public yourToken;
    //giá ta định nghĩa: 1ETH = 100 yourToken
    uint256 public constant tokensPerEth = 100;
    //event khi có người mua hàng
    event BuyTokens(address buyer, uint256 amountOfETH, uint256 amountOfTokens);

    //cp3: thêm event bán
    event SellTokens(address seller, uint256 amountOfTokens, uint256 amountOfETH);

    //khởi tạo địa chỉ Token và chủ sở hữu
    constructor(address tokenAddress) Ownable(msg.sender){
        yourToken = YourToken(tokenAddress);
    }

    //hàm payable để mua token
    function buyTokens() public payable {
        //tính toán lượng token khách hàng nhận được
        uint256 amountOfTokens = msg.value * tokensPerEth;

        //kiểm tra xem Vendor còn Token không?
        uint256 vendorBalance = yourToken.balanceOf(address(this));
        require(vendorBalance >= amountOfTokens, "Vendor het Token roi!");

        //chuyển Token cho khách
        (bool sent) = yourToken.transfer(msg.sender, amountOfTokens);
        require(sent, "Giao dich that bai");

        //thông báo
        emit BuyTokens(msg.sender, msg.value, amountOfTokens);
    }

    //hàm onlyOwner để chủ sở hữu rút ETH về
    function withdraw() public onlyOwner {
        //lấy toàn bộ ETH đang có trong máy
        uint256 ownerBalance = address(this).balance;
        require(ownerBalance > 0, "May khong co dong nao");

        //gửi về cho chủ sở hữu
        (bool sent,) = msg.sender.call{value: ownerBalance}("");
        require(sent, "Rut tien that bai");
    }

    //hàm bán
    function sellTokens(uint256 _amount) public {
        require(_amount > 0, "Phai ban nhieu hon 0");
        
        uint256 amountOfETH = _amount / tokensPerEth;

        require(address(this).balance >= amountOfETH, "May khong du ETH de thu mua");

        //dùng transferFrom: chuyển từ msg.sender -> address(this)
        //điều kiện: khách phải Approve trước thì lệnh này mới chạy được
        (bool sent) = yourToken.transferFrom(msg.sender, address(this), _amount);
        require(sent, "Khong the lay Token, ban da Approve chua?");

        //trả eth
        (bool success,) = msg.sender.call{value: amountOfETH}("");
        require(success, "Khong the tra ETH");

        //thông báo
        emit SellTokens(msg.sender, _amount, amountOfETH);
    }
}
