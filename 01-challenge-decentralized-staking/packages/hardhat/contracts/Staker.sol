// SPDX-License-Identifier: MIT
pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

contract Staker {
    ExampleExternalContract public exampleExternalContract;

    //khai báo biến trạng thái
    //cp1
    mapping(address => uint256) public balances; //map đóng vai trò như sổ cái, lưu số tiền góp mỗi người
    uint256 public constant threshold = 1 ether; //mục tiêu góp đủ 1 ether
    //cp2
    uint256 public deadline = block.timestamp + 72 hours; //tạm để 30s test cho nhanh
    bool public openForWithdraw = false; //lưu trạng thái

    //khai báo hàm event
    event Stake(address indexed sender, uint256 amount);

    constructor(address exampleExternalContractAddress) {
        exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
    }

    //(Yêu cầu phần "It's a trap!")
    //kiểm tra xem External Contract đã hoàn thành rồi -> (completed = true) thì chặn không cho chạy tiếp
    modifier notCompleted() {
        bool completed = exampleExternalContract.completed();
        require(!completed, "External contract da thanh cong!");
        _;
    }

    //core checkpoint 1: event stake
    function stake() public payable {
        //cộng dồn tiền stake
        balances[msg.sender] += msg.value;

        //thông báo với frontend
        emit Stake(msg.sender, msg.value);
    }

    //core checkpoint 2: hàm execute
    function execute() public {
        //buộc phải hết giờ mới được bấm
        require(block.timestamp >= deadline, "Chua den deadline");

        //đảm bảo 1 lần duy nhất
        require(!openForWithdraw, "Da execute roi!");

        //logic chính: đạt chỉ tiêu hay không
        if(address(this).balance >= threshold) {
            //NẾU ĐẠT -> chuyển tất cho external contract
            exampleExternalContract.complete{value: address(this).balance}();
        } else {
            //NẾU KHÔNG -> cho phép mọi người rút về
            openForWithdraw = true;
        }
    }

    //helper function cho frontend hiển thị
    function timeLeft() public view returns (uint256) {
        if (block.timestamp >= deadline) {
            return 0; //đã hết giờ
        }
        return deadline - block.timestamp; //timeleft
    }

    //nếu không đạt yêu cầu, cho phép withdraw
    function withdraw() public {
        //chỉ khi hết deadline và không đạt
        require(openForWithdraw, "Khong duoc phep rut tien");
        
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Ban khong gop tien, sao rut?");

        //reset số dư trước khi chuyển
        balances[msg.sender] = 0;

        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "Loi chuyen tien");
    }

    //core checkpoint 3: nhận tiền withdraw
    receive() external payable {
        stake();
    }
}
