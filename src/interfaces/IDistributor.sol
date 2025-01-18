// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import {Asset, AssetType} from "./types.sol";

// 分配算法接口
interface IDistributor {
    function distribute(
        address user, // 领取者地址 (msg.sender)
        Asset[] memory asset, // 资产信息 (来自红包配置)
        uint256 totalShares, // 总份数 (来自红包配置)
        uint256 claimedShares, // 已领取份数 (来自红包状态)
        uint256 claimedAmounts, // 已领取数量 (来自红包状态)
        bytes calldata configData // 分配器配置数据 (来自DistributeConfig)
    )
        external
        view
        returns (DistributeResult[] memory results, uint256 distributedAmounts);
}

// 分配结果结构
struct DistributeResult {
    AssetType assetType; // 资产类型
    address token; // 代币地址
    uint256 tokenId; // for ERC721/1155
    uint256 amount; // for ERC20/1155
}

// 分配配置
struct DistributeConfig {
    address distributor; // 分配算法合约地址
    bytes data; // 分配参数数据，取决于分配算法的数据结构
}
