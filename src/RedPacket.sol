// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IERC20} from "@oz/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@oz/contracts/interfaces/IERC721.sol";
import {IERC1155} from "@oz/contracts/interfaces/IERC1155.sol";
import {SafeERC20} from "@oz/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@oz/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@solmate/utils/ReentrancyGuard.sol";
import "./interfaces/IRedPacket.sol";

/**
 * @title RedPacket
 * @dev Implementation of the RedPacket contract
 * This contract handles the core logic for creating and claiming red packets
 */
contract RedPacket is IRedPacket, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public factory;

    // 基础信息
    address public creator;
    RedPacketConfig[] public configs;
    uint256 public createTime;
    bool public isActive;

    // 领取状态
    mapping(uint256 => uint256) public claimedShares; // redPacketIndex => claimed shares
    mapping(uint256 => mapping(address => bool)) public claimed; // redPacketIndex => user => claimed

    // trigger验证状态
    mapping(uint256 => bool) public triggerValidated; // redPacketIndex => isValidated

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    modifier whenActive(uint256 redPacketIndex) {
        // TODO: 允许owner修改active
        require(isActive, "RP: Not active");

        uint256 startTime = configs[redPacketIndex].base.startTime;
        uint256 durationTime = configs[redPacketIndex].base.durationTime;
        require(block.timestamp >= startTime, "RP: Not started");
        require(block.timestamp <= startTime + durationTime, "RP: Expired");
        _;
    }

    function initialize(
        RedPacketConfig[] calldata _configs,
        address _creator
    ) external initializer {
        factory = msg.sender;

        // 设置基础配置
        for (uint i = 0; i < _configs.length; i++) {
            configs.push(_configs[i]);
        }
        creator = _creator;
        createTime = block.timestamp;
        isActive = true;
    }

    /// Core functions
    // 领取红包
    function claim(
        uint256 redPacketIndex,
        bytes[] calldata accessProofs
    )
        external
        whenActive(redPacketIndex)
        nonReentrant
        returns (IDistributor.DistributeResult[] memory results)
    {
        RedPacketConfig storage config = configs[redPacketIndex];

        // 检查是否已领取
        if (claimed[redPacketIndex][msg.sender]) revert AlreadyClaimed();

        // 检查剩余份数
        uint256 remainingShares = config.base.shares -
            claimedShares[redPacketIndex];
        if (remainingShares == 0) revert NoRemainingShares();

        // 验证触发条件
        if (!triggerValidated[redPacketIndex]) {
            _validateTriggers(config.base.triggers);
            // 标记为已触发
            triggerValidated[redPacketIndex] = true;
        }

        // 验证访问控制
        _validateAccess(config.base.access, msg.sender, accessProofs);

        // 计算分配结果
        results = _calculateDistribution(
            redPacketIndex,
            config.base.distribute,
            config.assets,
            config.base.shares
        );

        // 更新状态
        claimed[redPacketIndex][msg.sender] = true;
        claimedShares[redPacketIndex]++;

        // 转移资产
        _transferAssets(msg.sender, results);

        emit Claimed(msg.sender, redPacketIndex, results);
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
        uint256 redPacketIndex,
        DistributeConfig storage distribute,
        Asset[] storage assets,
        uint256 totalShares
    ) internal view returns (IDistributor.DistributeResult[] memory results) {
        results = IDistributor(distribute.distributor).distribute(
            msg.sender,
            assets,
            totalShares,
            claimedShares[redPacketIndex],
            distribute.data
        );
    }

    // 转移资产
    function _transferAssets(
        address to,
        IDistributor.DistributeResult[] memory results
    ) internal {
        for (uint256 i = 0; i < results.length; i++) {
            IDistributor.DistributeResult memory result = results[i];

            if (result.assetType == AssetType.Native) {
                (bool success, ) = to.call{value: result.amount}("");
                if (!success) revert TransferFailed();
            } else if (result.assetType == AssetType.ERC20) {
                IERC20(result.token).safeTransfer(to, result.amount);
            } else if (result.assetType == AssetType.ERC721) {
                IERC721(result.token).safeTransferFrom(
                    address(this),
                    to,
                    result.tokenId
                );
            } else if (result.assetType == AssetType.ERC1155) {
                IERC1155(result.token).safeTransferFrom(
                    address(this),
                    to,
                    result.tokenId,
                    result.amount,
                    ""
                );
            }
        }
    }

    // 查询功能
    function getRemainingShares(
        uint256 redPacketIndex
    ) external view returns (uint256) {
        return
            configs[redPacketIndex].base.shares - claimedShares[redPacketIndex];
    }

    function getRedPacketInfo(
        uint256 redPacketIndex
    )
        external
        view
        returns (
            address _creator,
            RedPacketConfig memory config,
            uint256 _createTime,
            bool _isActive,
            uint256 _claimedShares
        )
    {
        return (
            creator,
            configs[redPacketIndex],
            createTime,
            isActive,
            claimedShares[redPacketIndex]
        );
    }

    receive() external payable {}
}
