// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "../interfaces/IDistributor.sol";
import "../libraries/AssetDistributor.sol";

/// @title RandomDistributor
/// @notice A distributor that randomly allocates assets using a two-average algorithm
contract RandomDistributor is IDistributor {
    error InvalidConfig();
    error InsufficientMinDistribution();
    error DistributedAmountOutOfRange(uint256 amount, uint256 min, uint256 max);

    struct RandomConfig {
        uint256 minAmount; // 最小分配金额
    }

    /// @inheritdoc IDistributor
    function distribute(
        address user,
        Asset[] calldata assets,
        uint256 totalShares,
        uint256 claimedShares,
        uint256 claimedAmounts,
        bytes calldata configData
    )
        external
        view
        returns (DistributeResult[] memory results, uint256 distributedAmounts)
    {
        uint256 minAmount;
        uint256 remainingAmount;
        uint256 remainingShares;
        {
            RandomConfig memory config = abi.decode(configData, (RandomConfig));
            minAmount = config.minAmount;
            if (minAmount == 0) revert InvalidConfig();

            // 计算总资产和剩余资产
            uint256 totalAmount = AssetDistributor.calculateTotalAmount(assets);
            remainingAmount = totalAmount - claimedAmounts;
            remainingShares = totalShares - claimedShares;

            // 验证剩余资产足够最小分配
            if (remainingAmount < remainingShares * minAmount) {
                revert InsufficientMinDistribution();
            }
        }

        // 计算本次分配金额
        uint256 amount = _calculateAmount(
            user,
            minAmount,
            remainingAmount,
            remainingShares
        );

        // 提取资产
        results = AssetDistributor.distributeAssets(
            assets,
            claimedAmounts,
            amount
        );
        distributedAmounts = amount;
    }

    /// @dev 计算分配金额
    function _calculateAmount(
        address user,
        uint256 minAmount,
        uint256 remainingAmount,
        uint256 remainingShares
    ) internal view returns (uint256) {
        if (remainingShares == 1) {
            // 最后一份，直接分配剩余金额
            return remainingAmount;
        }
        // 计算随机金额
        // 二倍均值法计算上限
        uint256 max = (remainingAmount / remainingShares) * 2;
        // 确保剩余金额足够其他份额的最小金额
        uint256 minRemaining = (remainingShares - 1) * minAmount;
        uint256 safeMax = remainingAmount - minRemaining;
        if (max > safeMax) {
            max = safeMax;
        }

        // 生成随机数
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.prevrandao,
                    gasleft(),
                    user,
                    msg.sender
                )
            )
        );

        // 计算随机金额 [minAmount, max]
        uint256 amount = minAmount + (random % (max - minAmount + 1));
        if (amount < minAmount || amount > max) {
            revert DistributedAmountOutOfRange(amount, minAmount, max);
        }

        return amount;
    }
}
