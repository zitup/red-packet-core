// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "../interfaces/ITrigger.sol";

// 通用触发检查只是初步概念，暂时不会使用。
/// @title StateTrigger
/// @notice A generic validator for on-chain state validation
contract StateTrigger is ITrigger {
    error InvalidTriggerData();
    error CallFailed();
    error InvalidCompareType();

    enum CompareType {
        Uint256, // 数值比较
        Bytes // 字节比较
    }

    enum CompareOp {
        Eq, // 等于
        Gt, // 大于
        Lt, // 小于
        Gte, // 大于等于
        Lte, // 小于等于
        Neq // 不等于
    }

    struct StateCheck {
        address target; // 目标合约
        bytes callData; // 调用数据
        CompareType compareType; // 比较类型
        CompareOp op; // 比较操作符
        bytes compareValue; // 比较值
    }

    struct StateCondition {
        StateCheck[] checks; // 多个检查
        bool isAnd; // true: 所有检查都必须通过, false: 任一检查通过即可
    }

    function validate(bytes calldata triggerData) external view returns (bool) {
        if (triggerData.length == 0) revert InvalidTriggerData();

        StateCondition memory condition = abi.decode(
            triggerData,
            (StateCondition)
        );

        bool result = condition.isAnd;

        for (uint256 i = 0; i < condition.checks.length; i++) {
            StateCheck memory check = condition.checks[i];
            bool checkResult = _validateCheck(check);

            if (condition.isAnd) {
                result = result && checkResult;
                if (!result) break;
            } else {
                result = result || checkResult;
                if (result) break;
            }
        }

        return result;
    }

    function _validateCheck(
        StateCheck memory check
    ) internal view returns (bool) {
        // 调用目标合约
        (bool success, bytes memory returnData) = check.target.staticcall(
            check.callData
        );
        if (!success) revert CallFailed();

        // 根据比较类型执行不同的比较逻辑
        if (check.compareType == CompareType.Uint256) {
            return _compareUint256(returnData, check.compareValue, check.op);
        } else if (check.compareType == CompareType.Bytes) {
            // bytes类型只支持相等比较
            if (check.op != CompareOp.Eq) revert InvalidCompareType();
            return _compareBytes(returnData, check.compareValue);
        }

        revert InvalidCompareType();
    }

    function _compareUint256(
        bytes memory returnData,
        bytes memory compareValue,
        CompareOp op
    ) internal pure returns (bool) {
        uint256 returnValue = abi.decode(returnData, (uint256));
        uint256 targetValue = abi.decode(compareValue, (uint256));

        if (op == CompareOp.Eq) return returnValue == targetValue;
        if (op == CompareOp.Gt) return returnValue > targetValue;
        if (op == CompareOp.Lt) return returnValue < targetValue;
        if (op == CompareOp.Gte) return returnValue >= targetValue;
        if (op == CompareOp.Lte) return returnValue <= targetValue;
        if (op == CompareOp.Neq) return returnValue != targetValue;

        return false;
    }

    function _compareBytes(
        bytes memory returnData,
        bytes memory compareValue
    ) internal pure returns (bool) {
        return keccak256(returnData) == keccak256(compareValue);
    }
}
