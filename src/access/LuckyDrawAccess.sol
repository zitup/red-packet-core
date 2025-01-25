// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IAccess.sol";

contract LuckyDrawAccess is IAccess {
    error InvalidProbability();

    struct LuckyDrawConfig {
        uint16 probability; // 中奖概率 (1-9999, 表示0.01%-99.99%)
    }

    /// @inheritdoc IAccess
    function validate(
        address user,
        bytes calldata,
        bytes calldata configData
    ) external view returns (bool) {
        LuckyDrawConfig memory config = abi.decode(
            configData,
            (LuckyDrawConfig)
        );

        uint16 probability = config.probability;

        // 验证概率范围 (1-9999)
        if (probability == 0 || probability > 9999) {
            revert InvalidProbability();
        }

        return _isWinner(user, probability);
    }

    /// @notice Determines if user wins the draw
    function _isWinner(
        address user,
        uint16 probability
    ) internal view returns (bool) {
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    gasleft(),
                    user,
                    msg.sender,
                    "win" // 区分分配金额的随机数
                )
            )
        );

        return (random % 10000) < probability;
    }
}
