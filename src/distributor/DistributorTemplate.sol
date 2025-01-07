// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IDistributor.sol";

contract DistributorTemplate is IDistributor {
    function distribute(
        address user,
        Asset[] memory asset,
        uint256 totalShares,
        uint256 claimedShares,
        bytes calldata configData
    ) external pure returns (DistributeResult[] memory) {
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
