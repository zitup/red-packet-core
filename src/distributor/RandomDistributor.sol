// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IDistributor.sol";

contract RandomDistributor is IDistributor {
    struct RandomDistributeConfig {
        uint256 minAmount; // 最小金额
        uint256 maxAmount; // 最大金额
    }

    function distribute(
        address user,
        Asset[] memory asset,
        uint256 totalShares,
        uint256 claimedShares,
        bytes calldata data
    ) external view returns (DistributeResult[] memory) {
        RandomDistributeConfig memory distributeConfig = abi.decode(
            data,
            (RandomDistributeConfig)
        );

        // 确保剩余金额足够支付最小金额
        uint256 remainingShares = totalShares - claimedShares;
        // require(
        //     remainingAmount >= distributeConfig.minAmount * remainingShares,
        //     "Insufficient remaining"
        // );

        // 使用随机数生成器计算金额
        // return
        //     _calculateRandomAmount(
        //         minAmount,
        //         maxAmount,
        //         remainingAmount,
        //         remainingShares
        //     );

        IDistributor.DistributeResult[]
            memory results = new IDistributor.DistributeResult[](1);
        results[0] = DistributeResult({
            assetType: AssetType.ERC20,
            token: address(0),
            tokenId: 0,
            amount: 10
        });
        return results;
    }
}
