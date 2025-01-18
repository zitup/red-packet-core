// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "../interfaces/IDistributor.sol";
import {AssetDistributor} from "../libraries/AssetDistributor.sol";

/// @title FixedDistributor
/// @notice Distributes assets in fixed amounts
contract FixedDistributor is IDistributor {
    /// @inheritdoc IDistributor
    function distribute(
        address,
        Asset[] calldata assets,
        uint256 totalShares,
        uint256,
        uint256 claimedAmounts,
        bytes calldata
    )
        external
        pure
        returns (DistributeResult[] memory results, uint256 distributedAmounts)
    {
        // 计算总资产数量
        uint256 totalAmount = AssetDistributor.calculateTotalAmount(assets);

        // 计算每份的数量（向下取整）
        uint256 amountPerShare = totalAmount / totalShares;

        // 使用AssetHandler提取资产
        results = AssetDistributor.distributeAssets(
            assets,
            claimedAmounts, // 已领取的数量
            amountPerShare // 本次领取的数量
        );
        distributedAmounts = amountPerShare;
    }
}
