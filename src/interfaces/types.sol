// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "./ITrigger.sol";
import "./IAccess.sol";
import "./IDistributor.sol";

enum AssetType {
    None,
    Native,
    ERC20,
    ERC721,
    ERC1155
}

// 原子资产
struct Asset {
    AssetType assetType; // ERC20/721/1155
    address token;
    uint256 tokenId; // for NFT
    uint256 amount; // for ERC20/1155
}

// 通用基础参数
struct BaseConfig {
    string name;
    string message;
    uint256 startTime;
    uint256 durationTime;
    uint256 shares; // 红包份数
    AccessConfig[] access; // 支持多个访问控制
    TriggerConfig[] triggers; // 支持多个触发条件
    DistributeConfig distribute; // 分配配置
}

// 一个 RedPacketConfig 表示一个红包，可以看作一个池子，池子中的资产使用相同的份额和控制规则（access/trigger/distribute）
// 当有多个 RedPacketConfig ，每个池子的份额和控制规则隔离
// 比如：
/**
 * RedPacketConfig[] = [
    // 红包1：USDT红包池
    {
        base: {...},
        assets: [USDT资产]
    },
    // 红包2：NFT红包池
    {
        base: {...},
        assets: [NFT1, NFT2, NFT3]
    }
]
 */
struct RedPacketConfig {
    BaseConfig base;
    Asset[] assets; // 单个资产时长度为1，长度大于1时为同系列资产，比如USDT/USDC或一个NFT系列，属于同一个池子
}

// // 基础红包
// // ERC20 红包
// struct ERC20RedPacketConfig {
//     BaseConfig base;
//     Asset asset; // token资产信息
//     uint256 shares; // 红包份数
//     DistributeConfig distribute; // 分配配置
// }

// // ERC721 红包
// struct ERC721RedPacketConfig {
//     BaseConfig base;
//     Asset asset; // NFT资产信息
//     // NFT红包只支持一对一赠送，无需额外参数
// }

// // ERC1155
// struct ERC1155RedPacketConfig {
//     BaseConfig base;
//     Asset asset; // token资产信息
//     uint256 shares; // 红包份数
//     DistributeConfig distribute; // 分配配置
// }

// // 系列红包
// struct SeriesRedPacketConfig {
//     BaseConfig base;
//     Asset[] assets; // 同系列资产列表
//     uint256 shares; // 红包份数
//     DistributeConfig distribute; // 分配配置
// }

// // 定制红包
// struct CustomRedPacketConfig {
//     RedPacketConfig[] subRedPackets; // 子红包列表
// }

struct RedPacketInfo {
    address creator;
    RedPacketConfig[] configs;
    uint256 createTime;
    uint256[] claimedShares;
}
