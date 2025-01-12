// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "../interfaces/IAccess.sol";

// 通用访问校验只是初步概念，暂时不会使用。
/// @title StateAccess
/// @notice A generic validator for state-based access control
contract StateAccess is IAccess {
    error InvalidAccessData();
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

    struct AccessCondition {
        StateCheck[] checks; // 多个检查
        bool isAnd; // true: 所有检查都必须通过, false: 任一检查通过即可
    }

    /// @notice Validates if user meets the state requirements
    /// @param user The user to validate
    /// @param {data} Unused in state validation
    /// @param accessData Encoded AccessCondition
    function validate(
        address user,
        bytes calldata,
        bytes calldata accessData
    ) external view returns (bool) {
        if (accessData.length == 0) revert InvalidAccessData();

        AccessCondition memory condition = abi.decode(
            accessData,
            (AccessCondition)
        );

        bool result = condition.isAnd;

        for (uint256 i = 0; i < condition.checks.length; i++) {
            StateCheck memory check = condition.checks[i];

            // 替换callData中的占位符地址为实际用户地址
            bytes memory actualCallData = _replaceUserAddress(
                check.callData,
                user
            );

            check.callData = actualCallData;
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
        (bool success, bytes memory returnData) = check.target.staticcall(
            check.callData
        );
        if (!success) revert CallFailed();

        if (check.compareType == CompareType.Uint256) {
            return _compareUint256(returnData, check.compareValue, check.op);
        } else if (check.compareType == CompareType.Bytes) {
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

    /// @notice Replaces placeholder address with actual user address in callData
    /// @dev This function replaces a placeholder address(1) with the actual user address in the callData
    ///      The process works as follows:
    ///      1. Creates a new bytes array with the same length as input callData
    ///      2. Iterates through callData in 32-byte words
    ///      3. For each word, checks if it contains the placeholder address
    ///      4. If found, replaces the placeholder with the user address
    ///      5. Preserves all other data in the callData unchanged
    /// @param callData The original callData with placeholder address(1)
    /// @param user The actual user address to replace the placeholder
    /// @return result The modified callData with user address
    function _replaceUserAddress(
        bytes memory callData,
        address user
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(callData.length);
        assembly {
            // 获取callData长度并存储到新数组
            let len := mload(callData)
            mstore(result, len)

            // 遍历所有32字节的字
            for {
                let i := 0
            } lt(i, len) {
                i := add(i, 32)
            } {
                // 加载当前32字节字
                // add(callData, 32) 跳过长度字段
                // add(..., i) 移动到当前位置
                let word := mload(add(callData, add(32, i)))

                // 检查当前字是否包含占位符地址(address(1))
                // and(word, 0xfff...fff) 提取最后20字节(地址部分)
                // eq(..., 0x01) 检查是否等于address(1)
                if eq(
                    and(word, 0xffffffffffffffffffffffffffffffffffffffff),
                    0x0000000000000000000000000000000000000001
                ) {
                    // 替换地址
                    // not(0xfff...fff) 创建地址位的掩码
                    // and(word, not(0xfff...fff)) 清除原地址
                    // or(..., user) 插入新地址
                    word := or(
                        and(
                            word,
                            not(0xffffffffffffffffffffffffffffffffffffffff)
                        ),
                        user
                    )
                }

                // 存储处理后的字（无论是否被修改）
                mstore(add(result, add(32, i)), word)
            }
        }
        return result;
    }
}
