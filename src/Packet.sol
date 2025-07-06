// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@oz/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@solmate/utils/ReentrancyGuard.sol";
import "./interfaces/IPacket.sol";

/**
 * @title Packet
 * @dev Implementation of the Packet contract
 * This contract handles the core logic for creating and claiming packets
 */
contract Packet is IPacket, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public factory;

    // 基础信息
    address public creator;
    PacketConfig[] public configs;
    uint256 public createTime;

    // 领取状态
    mapping(uint256 => uint256) public claimedShares; // packetIndex => claimed shares
    mapping(uint256 => uint256) public claimedAmounts; // packetIndex => claimed shares
    mapping(uint256 => mapping(address => bool)) public claimed; // packetIndex => user => claimed

    // trigger验证状态
    mapping(uint256 => bool) public triggerValidated; // packetIndex => isValidated

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    modifier whenActive(uint256 packetIndex) {
        uint256 startTime = configs[packetIndex].base.startTime;
        uint256 durationTime = configs[packetIndex].base.durationTime;
        require(block.timestamp >= startTime, "RP: Not started");
        require(block.timestamp <= startTime + durationTime, "RP: Expired");
        _;
    }

    function initialize(
        PacketConfig[] calldata _configs,
        address _creator
    ) external initializer {
        factory = msg.sender;

        // 设置基础配置
        for (uint i = 0; i < _configs.length; i++) {
            configs.push(_configs[i]);
        }
        creator = _creator;
        createTime = block.timestamp;
    }

    function getPacketInfo()
        external
        view
        returns (PacketInfo memory packetInfo)
    {
        uint256 totalPackets = configs.length;
        uint256[] memory allClaimedShares = new uint256[](totalPackets);
        for (uint256 i = 0; i < totalPackets; i++) {
            allClaimedShares[i] = claimedShares[i];
        }

        packetInfo = PacketInfo({
            creator: creator,
            configs: configs,
            createTime: createTime,
            claimedShares: allClaimedShares,
            isExpired: isExpired()
        });
    }

    /// @notice 创建者一次性提取所有资产
    /// @dev 只有在所有红包过期后才能调用
    /// @param tokens 要提取的ERC20代币地址列表
    /// @param recipient 接受者地址
    function withdrawAllAssets(
        address[] calldata tokens,
        address recipient
    ) external onlyCreator nonReentrant {
        if (recipient == address(0)) {
            recipient = msg.sender;
        }

        // 检查红包是否已过期
        if (!isExpired()) revert NotExpired();

        address packet = address(this);

        // 提取原生代币
        uint256 balance = packet.balance;
        if (balance > 0) {
            (bool success, ) = recipient.call{value: balance}("");
            if (!success) revert EthTransferFailed();
        }

        // 提取ERC20代币
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = IERC20(tokens[i]).balanceOf(packet);
            if (tokenBalance > 0) {
                IERC20(tokens[i]).safeTransfer(recipient, tokenBalance);
            }
        }
    }

    // 查询功能
    /// @notice 检查所有红包是否已过期
    function isExpired() public view returns (bool) {
        uint256 totalPackets = configs.length;
        for (uint256 i = 0; i < totalPackets; i++) {
            if (
                block.timestamp <=
                configs[i].base.startTime + configs[i].base.durationTime
            ) {
                return false;
            }
        }
        return true;
    }

    /// @notice 领取红包
    /// @param packetIndex 红包索引
    /// @param accessProofs 访问控制证明
    function claim(
        uint256 packetIndex,
        bytes[] calldata accessProofs
    ) public whenActive(packetIndex) nonReentrant returns (bool) {
        PacketConfig storage config = configs[packetIndex];

        // 检查是否已领取
        if (claimed[packetIndex][msg.sender]) revert AlreadyClaimed();

        // 检查剩余份数
        uint256 remainingShares = config.base.shares -
            claimedShares[packetIndex];
        if (remainingShares == 0) revert NoRemainingShares();

        // 验证触发条件
        if (!triggerValidated[packetIndex]) {
            _validateTriggers(config.base.triggers);
            // 标记为已触发
            triggerValidated[packetIndex] = true;
        }

        // 验证访问控制
        _validateAccess(config.base.access, msg.sender, accessProofs);

        // 计算分配结果
        DistributeResult[] memory results;
        uint256 distributedAmounts;
        (results, distributedAmounts) = _calculateDistribution(
            packetIndex,
            config.base.distribute,
            config.assets,
            config.base.shares
        );

        // 更新状态
        claimed[packetIndex][msg.sender] = true;
        claimedShares[packetIndex]++;
        claimedAmounts[packetIndex] += distributedAmounts;

        // 转移资产
        _transferAssets(msg.sender, results);

        emit Claimed(msg.sender, packetIndex, results);
        return true;
    }

    /// @notice 一次性领取所有红包
    function claimAll(bytes[][] calldata accessProofs) external nonReentrant {
        uint256 totalPackets = configs.length;

        for (uint256 i = 0; i < totalPackets; i++) {
            // 跳过已领取的红包
            if (claimed[i][msg.sender]) continue;

            // 尝试领取每个红包
            // 注意：即使某个红包领取失败，继续尝试其他红包
            claim(i, accessProofs[i]);
        }
        emit ClaimAll(msg.sender, totalPackets);
    }

    // TODO: 这里有一个测试用例，校验三个控制的view修饰符是否起作用，通过调用一个外部控制合约，改变合约状态验证
    // 验证访问控制
    function _validateAccess(
        AccessConfig[] memory accessConfigs,
        address user,
        bytes[] calldata proofs
    ) internal view {
        for (uint256 i = 0; i < accessConfigs.length; i++) {
            bool valid = IAccess(accessConfigs[i].validator).validate(
                user,
                proofs[i],
                accessConfigs[i].data
            );
            if (!valid) revert AccessDenied(accessConfigs[i].validator);
        }
    }

    // 验证触发条件
    function _validateTriggers(TriggerConfig[] memory triggers) internal view {
        for (uint256 i = 0; i < triggers.length; i++) {
            bool valid = ITrigger(triggers[i].validator).validate(
                triggers[i].data
            );
            if (!valid) revert TriggerConditionNotMet(triggers[i].validator);
        }
    }

    // 计算分配结果
    function _calculateDistribution(
        uint256 packetIndex,
        DistributeConfig storage distribute,
        Asset[] storage assets,
        uint256 totalShares
    )
        internal
        view
        returns (DistributeResult[] memory results, uint256 distributedAmounts)
    {
        (results, distributedAmounts) = IDistributor(distribute.distributor)
            .distribute(
                msg.sender,
                assets,
                totalShares,
                claimedShares[packetIndex],
                claimedAmounts[packetIndex],
                distribute.data
            );
    }

    // 转移资产
    function _transferAssets(
        address to,
        DistributeResult[] memory results
    ) internal {
        for (uint256 i = 0; i < results.length; i++) {
            DistributeResult memory result = results[i];

            if (result.assetType == AssetType.Native) {
                (bool success, ) = to.call{value: result.amount}("");
                if (!success) revert EthTransferFailed();
            } else if (result.assetType == AssetType.ERC20) {
                IERC20(result.token).safeTransfer(to, result.amount);
            }
        }
    }

    receive() external payable {}
}
