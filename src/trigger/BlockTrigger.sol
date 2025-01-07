// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ITrigger} from "../interfaces/ITrigger.sol";

contract BlockTrigger is ITrigger {
    struct BlockCondition {
        uint256 targetBlock;
    }

    function validate(
        bytes calldata data
    ) external view override returns (bool) {
        BlockCondition memory condition = abi.decode(data, (BlockCondition));
        // 验证逻辑
        // current block >= targetBlock
        return true;
    }
}
