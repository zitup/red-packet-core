// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ITrigger} from "../interfaces/ITrigger.sol";

contract PriceTrigger is ITrigger {
    struct PriceCondition {
        address token;
        uint256 threshold;
        bool isAbove;
    }

    function validate(
        bytes calldata data
    ) external view override returns (bool) {
        PriceCondition memory condition = abi.decode(data, (PriceCondition));
        // 验证逻辑
        // current token price > threshold
        return true;
    }
}
