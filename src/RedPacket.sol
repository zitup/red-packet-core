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
    mapping(uint256 => uint256) public claimedAmounts; // redPacketIndex => claimed shares
    mapping(uint256 => mapping(address => bool)) public claimed; // redPacketIndex => user => claimed

    // trigger验证状态
    mapping(uint256 => bool) public triggerValidated; // redPacketIndex => isValidated

    modifier onlyFactory() {
        if (msg.sender != factory) revert NotFactory();
        _;
    }

    modifier onlyCreator() {
        if (msg.sender != creator) revert NotCreator();
        _;
    }

    modifier whenActive(uint256 redPacketIndex) {
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
    ) public whenActive(redPacketIndex) nonReentrant returns (bool) {
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
        DistributeResult[] memory results;
        uint256 distributedAmounts;
        (results, distributedAmounts) = _calculateDistribution(
            redPacketIndex,
            config.base.distribute,
            config.assets,
            config.base.shares
        );

        // 更新状态
        claimed[redPacketIndex][msg.sender] = true;
        claimedShares[redPacketIndex]++;
        claimedAmounts[redPacketIndex] += distributedAmounts;

        // 转移资产
        _transferAssets(msg.sender, results);

        emit Claimed(msg.sender, redPacketIndex, results);
        return true;
    }

    /// @notice 一次性领取所有红包
    function claimAll(bytes[][] calldata accessProofs) external nonReentrant {
        uint256 totalRedPackets = configs.length;

        for (uint256 i = 0; i < totalRedPackets; i++) {
            // 跳过已领取的红包
            if (claimed[i][msg.sender]) continue;

            // 尝试领取每个红包
            // 注意：即使某个红包领取失败，继续尝试其他红包
            claim(i, accessProofs[i]);
        }
        emit ClaimAll(msg.sender, totalRedPackets);
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
                claimedShares[redPacketIndex],
                claimedAmounts[redPacketIndex],
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

    /// @notice 创建者一次性提取所有资产
    /// @dev 只有在所有红包过期后才能调用
    /// @param tokens 要提取的ERC20代币地址列表
    /// @param nfts NFT代币提取配置，包含合约地址和tokenId
    /// @param erc1155s ERC1155代币提取配置，包含合约地址和tokenId
    /// @param recipient 接受者地址
    function withdrawAllAssets(
        address[] calldata tokens,
        NFTInfo[] calldata nfts,
        ERC1155Info[] calldata erc1155s,
        address recipient
    ) external onlyCreator nonReentrant {
        if (recipient == address(0)) {
            recipient = msg.sender;
        }

        // 检查红包是否已过期
        if (!isExpired()) revert NotExpired();

        address redPacket = address(this);

        // 提取原生代币
        uint256 balance = redPacket.balance;
        if (balance > 0) {
            (bool success, ) = recipient.call{value: balance}("");
            if (!success) revert EthTransferFailed();
        }

        // 提取ERC20代币
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = IERC20(tokens[i]).balanceOf(redPacket);
            if (tokenBalance > 0) {
                IERC20(tokens[i]).safeTransfer(recipient, tokenBalance);
            }
        }

        // 提取NFT
        for (uint256 i = 0; i < nfts.length; i++) {
            if (IERC721(nfts[i].token).ownerOf(nfts[i].tokenId) == redPacket) {
                IERC721(nfts[i].token).safeTransferFrom(
                    redPacket,
                    recipient,
                    nfts[i].tokenId
                );
            }
        }

        // 提取ERC1155
        for (uint256 i = 0; i < erc1155s.length; i++) {
            uint256 tokenBalance = IERC1155(erc1155s[i].token).balanceOf(
                redPacket,
                erc1155s[i].tokenId
            );
            if (tokenBalance > 0) {
                IERC1155(erc1155s[i].token).safeTransferFrom(
                    redPacket,
                    recipient,
                    erc1155s[i].tokenId,
                    tokenBalance,
                    ""
                );
            }
        }
    }

    // 查询功能
    /// @notice 检查所有红包是否已过期
    function isExpired() public view returns (bool) {
        uint256 totalRedPackets = configs.length;
        for (uint256 i = 0; i < totalRedPackets; i++) {
            if (
                block.timestamp <=
                configs[i].base.startTime + configs[i].base.durationTime
            ) {
                return false;
            }
        }
        return true;
    }

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
