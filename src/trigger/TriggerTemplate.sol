// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ITrigger} from "../interfaces/ITrigger.sol";

contract TriggerTemplate is ITrigger {
    struct SomeCondition {
        uint256 someField;
    }

    function validate(
        bytes calldata data
    ) external view override returns (bool) {
        SomeCondition memory condition = abi.decode(data, (SomeCondition));
        // 验证逻辑
        // someField follows the logic of our setup.
        return true;
    }
}
