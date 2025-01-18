// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "../interfaces/types.sol";

library AssetDistributor {
    /// @notice 从资产列表中分配指定数量的资产
    /// @param assets 可用资产列表
    /// @param claimedAmount 已被领取的数量
    /// @param requestedAmount 本次请求分配的数量
    /// @return results 分配结果列表
    function distributeAssets(
        Asset[] memory assets,
        uint256 claimedAmount,
        uint256 requestedAmount
    ) internal pure returns (DistributeResult[] memory results) {
        // 计算需要多少个资产来满足请求数量
        (
            uint256 startIndex,
            uint256 endIndex,
            uint256 remainingAmount,
            uint256 endAmount
        ) = _calculateDistributionRange(assets, claimedAmount, requestedAmount);

        // 创建结果数组
        results = new DistributeResult[](endIndex - startIndex + 1);

        // 填充结果
        for (uint256 i = startIndex; i <= endIndex; i++) {
            Asset memory asset = assets[i];
            uint256 amount;

            if (startIndex == endIndex) {
                amount = endAmount; // 当是同一个资产时，使用endAmount
            } else if (i == startIndex) {
                amount = remainingAmount;
            } else if (i == endIndex) {
                amount = endAmount;
            } else {
                amount = asset.amount;
            }

            results[i - startIndex] = DistributeResult({
                assetType: asset.assetType,
                token: asset.token,
                tokenId: asset.tokenId,
                amount: amount
            });
        }
    }

    /// @notice 计算资产分配的范围和数量
    /// @param assets 资产列表
    /// @param claimedAmount 已被领取的数量
    /// @param requestedAmount 本次请求分配的数量
    /// @return startIndex 起始资产索引
    /// @return endIndex 结束资产索引
    /// @return remainingAmount 起始资产的可用数量
    /// @return endAmount 结束资产需要使用的数量
    function _calculateDistributionRange(
        Asset[] memory assets,
        uint256 claimedAmount,
        uint256 requestedAmount
    )
        internal
        pure
        returns (
            uint256 startIndex,
            uint256 endIndex,
            uint256 remainingAmount,
            uint256 endAmount
        )
    {
        uint256 currentAmount = 0;
        uint256 i = 0;

        // 找到最后一个有未使用数量的资产索引
        while (i < assets.length && currentAmount < claimedAmount) {
            currentAmount += assets[i].amount;
            if (currentAmount < claimedAmount) {
                i++;
            }
        }
        startIndex = i;

        // 计算startIndex位置资产的剩余可用量
        remainingAmount = currentAmount - claimedAmount;

        if (remainingAmount >= requestedAmount) {
            endIndex = startIndex;
            endAmount = requestedAmount;
        } else {
            // 从startIndex开始，计算满足请求数量需要的资产
            currentAmount = remainingAmount; // 从剩余量开始计算
            i = startIndex + 1; // 从下一个资产开始
            while (i < assets.length && currentAmount < requestedAmount) {
                currentAmount += assets[i].amount;
                if (currentAmount < requestedAmount) {
                    i++;
                }
            }
            endIndex = i;
            // 计算endIndex位置需要使用的具体数量
            endAmount =
                assets[endIndex].amount -
                (currentAmount - requestedAmount);
        }
    }

    /// @notice Calculates total amount of all assets
    function calculateTotalAmount(
        Asset[] calldata assets
    ) internal pure returns (uint256 totalAmount) {
        uint256 length = assets.length;
        for (uint256 i = 0; i < length; i++) {
            totalAmount += assets[i].amount;
        }
    }
}
