// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "./ITrigger.sol";
import "./IAccess.sol";
import "./IDistributor.sol";

enum AssetType {
    None,
    Native,
    ERC20
}

// 原子资产
struct Asset {
    AssetType assetType; // ERC20
    address token;
    uint256 amount; // for ERC20
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

// 一个 PacketConfig 表示一个红包，可以看作一个池子，池子中的资产使用相同的份额和控制规则（access/trigger/distribute）
// 当有多个 PacketConfig ，每个池子的份额和控制规则隔离
// 比如：
/**
 * PacketConfig[] = [
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
struct PacketConfig {
    BaseConfig base;
    Asset[] assets; // 单个资产时长度为1，长度大于1时为同系列资产，比如USDT/USDC或一个NFT系列，属于同一个池子
}

struct PacketInfo {
    address creator;
    PacketConfig[] configs;
    uint256 createTime;
    uint256[] claimedShares;
    bool isExpired;
}
