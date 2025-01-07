// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// 访问控制接口
interface IAccess {
    function validate(
        address user,
        bytes calldata data,
        bytes calldata configData
    ) external view returns (bool);
}

// 访问控制配置
struct AccessConfig {
    address validator; // 验证器合约地址
    bytes data; // 验证数据
}
