// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@oz/contracts/access/Ownable.sol";
import {BeaconProxy} from "@oz/contracts/proxy/beacon/BeaconProxy.sol";
import {ISignatureTransfer as IPermit2} from "@permit2/interfaces/ISignatureTransfer.sol";
import {IPacketFactory} from "./interfaces/IPacketFactory.sol";
import "./interfaces/IPacket.sol";

/// @title PacketFactory
/// @notice Factory contract for creating packet proxies
contract PacketFactory is IPacketFactory, Ownable {
    // Beacon合约地址
    address public immutable beacon;

    IPermit2 public immutable PERMIT2;

    // 创建者数量
    uint256 public creatorsCount;
    // 所有红包
    address[] public packets;
    // 创建者的红包索引映射
    mapping(address => uint256[]) private creatorPacketIndices;

    // 协议费接收地址
    address public feeReceiver;

    // _permit: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    constructor(
        address _owner,
        address _beacon,
        address _permit,
        address _feeReceiver
    ) Ownable(_owner) {
        if (_beacon == address(0)) revert ZeroBeaconAddress();
        if (_permit == address(0)) revert ZeroPermitAddress();
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver();

        beacon = _beacon;
        PERMIT2 = IPermit2(_permit);
        feeReceiver = _feeReceiver;
    }

    /// @notice 获取所有红包地址
    /// @return 所有红包地址列表
    function getAllPackets() external view returns (address[] memory) {
        return packets;
    }

    /// @notice 获取指定创建者的所有红包地址
    /// @param creator 创建者地址
    function getPackets(
        address creator
    ) external view returns (address[] memory) {
        uint256[] memory indices = creatorPacketIndices[creator];
        address[] memory ownedPackets = new address[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            ownedPackets[i] = packets[indices[i]];
        }
        return ownedPackets;
    }

    /// @notice 计算指定份数的手续费（以ETH为单位）
    /// @param shares 红包份数
    /// @return feeInETH 手续费（以ETH为单位）
    function calculateFee(
        uint256 shares
    ) public pure returns (uint256 feeInETH) {
        return _calculateFee(shares);
    }

    // 设置协议费接收地址
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver();
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(_feeReceiver);
    }

    function createPacket(
        PacketConfig calldata config,
        bytes calldata permit
    ) public payable returns (address packet) {
        // # 1. 验证配置
        _validatePacketConfig(config);
        uint256 totalShares = config.base.shares;

        // # 2. 部署红包合约
        packet = _deployPacket();

        // # 3. 处理资产转移
        _transferAssets(packet, config, permit, totalShares);

        // # 4. 初始化红包合约
        IPacket(packet).initialize(config, msg.sender);
    }

    // 简化验证逻辑
    function _validatePacketConfig(PacketConfig calldata config) internal pure {
        // 基础检查
        if (config.assets.length == 0) revert NoAssets();
        if (config.base.shares == 0) revert InvalidShares();

        // 验证白名单模式
        if (config.base.accessType == AccessType.Whitelist) {
            if (config.base.merkleRoot == bytes32(0)) revert NoAccessControl();
        }

        // 验证资产金额
        for (uint i = 0; i < config.assets.length; i++) {
            if (config.assets[i].amount == 0) {
                revert InvalidTokenAmount(config.assets[i].token);
            }
        }
    }

    function _deployPacket() internal returns (address packet) {
        packet = address(new BeaconProxy(beacon, ""));

        address creator = _msgSender();
        if (creatorPacketIndices[creator].length == 0) {
            creatorsCount++;
        }

        packets.push(packet);
        creatorPacketIndices[creator].push(packets.length - 1);

        emit PacketCreated(packet, creator);
    }

    function _transferAssets(
        address packet,
        PacketConfig calldata config,
        bytes calldata permit,
        uint256 totalShares
    ) internal {
        uint256 expectedEthValue;
        (expectedEthValue) = _handleERC20Transfers(packet, config, permit);

        // 计算基于份数的手续费
        uint256 totalFee = _calculateFee(totalShares);

        // 检查并转移ETH（包含手续费）
        if (msg.value < (expectedEthValue + totalFee))
            revert InvalidEthAmount(expectedEthValue + totalFee);

        // 转移完整ETH金额到红包合约
        if (expectedEthValue > 0) {
            (bool success, ) = packet.call{value: expectedEthValue}("");
            if (!success) revert EthTransferFailed();
        }

        // 转移ETH手续费
        if (totalFee > 0) {
            (bool success, ) = feeReceiver.call{value: totalFee}("");
            if (!success) revert EthTransferFailed();
        }
    }

    function _handleERC20Transfers(
        address packet,
        PacketConfig calldata config,
        bytes calldata permit
    ) internal returns (uint256 expectedEthValue) {
        IPermit2.PermitBatchTransferFrom memory permitBatch;
        bytes memory signature;
        IPermit2.SignatureTransferDetails[] memory transferDetails;
        if (permit.length > 0) {
            (permitBatch, signature) = abi.decode(
                permit,
                (IPermit2.PermitBatchTransferFrom, bytes)
            );

            transferDetails = new IPermit2.SignatureTransferDetails[](
                permitBatch.permitted.length
            );
        }

        uint256 transferDetailsIndex = 0;

        for (uint256 j = 0; j < config.assets.length; j++) {
            Asset calldata asset = config.assets[j];

            if (asset.assetType == AssetType.Native) {
                expectedEthValue += asset.amount;
            } else if (asset.assetType == AssetType.ERC20) {
                // 转移完整金额到红包合约
                transferDetails[transferDetailsIndex++] = IPermit2
                    .SignatureTransferDetails({
                        to: packet,
                        requestedAmount: asset.amount
                    });
            }
        }

        // 执行ERC20转账
        if (transferDetailsIndex > 0) {
            PERMIT2.permitTransferFrom(
                permitBatch,
                transferDetails,
                msg.sender,
                signature
            );
        }
    }

    function _calculateFee(
        uint256 shares
    ) internal pure returns (uint256 feeInETH) {
        if (shares <= 100) {
            return 0.001 ether;
        } else if (shares <= 1000) {
            return 0.01 ether;
        } else {
            return 0.05 ether;
        }
    }

    receive() external payable {}
}
