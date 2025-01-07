// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

// 触发条件接口
interface ITrigger {
    function validate(bytes calldata data) external view returns (bool);
}

// 触发条件配置
struct TriggerConfig {
    address validator; // 触发条件验证器合约地址
    bytes data; // 触发条件数据
}
