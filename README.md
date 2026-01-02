by @lilsadfoqs


# Hướng dẫn chạy code cho tất cả các challenge

- Chạy `yarn generate`

![slide-images-3](https://github.com/user-attachments/assets/9386c6f4-04e4-4b72-893a-6ee8099e1628)

- Sau bước này tại `./packages/hardhat` 1 file `.env` được tạo:
```
DEPLOYER_PRIVATE_KEY_ENCRYPTED=...
```

- Ta cần tự thêm `ALCHEMY_API_KEY` và `ETHERSCAN_API_KEY` để `./packages/hardhat/.env` cuối cùng có dạng:
```
DEPLOYER_PRIVATE_KEY_ENCRYPTED=...
ALCHEMY_API_KEY=...
ETHERSCAN_API_KEY=...
```

- Thêm ở `./packages/nextjs`, tạo file `.env.local` như sau:
```
ALCHEMY_API_KEY=... (giống hệt cái Alchemy key bên trên)
```

- Chạy `yarn account` xác nhận đã được generate và kiểm tra lại địa chỉ

![slide-images-4](https://github.com/user-attachments/assets/040f84e0-d823-4329-9b95-a99b0ef0dda3)

- Dùng Faucet để Fauce 1 lượng vừa đủ SepETH (tùy bài mà lượng yêu cầu khác nhau)

![slide-images-6](https://github.com/user-attachments/assets/32de6501-8529-405b-a56d-51bfe969e648)

- Chạy `yarn deploy` contracts lên network

![slide-images-8](https://github.com/user-attachments/assets/70368881-894e-428d-9637-3f253ffc6aac)

- Cuối cùng deploy frontend lên Vercel bằng lệnh `yarn vercel` là có thể submit challenge
