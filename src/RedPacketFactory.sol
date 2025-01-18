// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {BeaconProxy} from "@oz/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC721} from "@oz/contracts/interfaces/IERC721.sol";
import {IERC1155} from "@oz/contracts/interfaces/IERC1155.sol";
import {ISignatureTransfer as IPermit2} from "@permit2/interfaces/ISignatureTransfer.sol";
import {IRedPacketFactory} from "./interfaces/IRedPacketFactory.sol";
import "./interfaces/IRedPacket.sol";

/// @title RedPacketFactory
/// @notice Factory contract for creating red packet proxies
contract RedPacketFactory is IRedPacketFactory {
    // Beacon合约地址
    address public immutable beacon;

    IPermit2 public immutable PERMIT2;

    // 存储所有创建者地址
    address[] public creators;
    // 用于检查地址是否已经是创建者
    mapping(address => bool) public isCreator;
    // creator => redPackets
    mapping(address => address[]) public redPackets;
    // redPacket => creator
    mapping(address => address) public redPacketCreator;

    // _permit: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    constructor(address _beacon, address _permit) {
        if (_beacon == address(0)) revert ZeroBeaconAddress();
        beacon = _beacon;
        PERMIT2 = IPermit2(_permit);
    }

    function createRedPacket(
        RedPacketConfig[] calldata configs,
        bytes calldata signature
    ) external returns (address redPacket) {
        if (configs.length == 0) revert EmptyConfigs();

        // # 1. 验证配置
        for (uint i = 0; i < configs.length; i++) {
            _validateRedPacketConfig(configs[i]);
        }

        // # 2. 部署红包合约
        redPacket = _deployRedPacket();

        // # 3. 处理资产转移
        _transferAssets(redPacket, configs, signature);

        // # 4. 初始化红包合约
        IRedPacket(redPacket).initialize(configs, msg.sender);
    }

    // 简单校验配置
    function _validateRedPacketConfig(
        RedPacketConfig calldata config
    ) internal pure {
        // 最基础的安全检查
        if (config.assets.length == 0) revert NoAssets();
        if (config.base.shares == 0) revert InvalidShares();
        if (config.base.distribute.distributor == address(0))
            revert InvalidDistributor();
        if (config.base.access.length < 1) revert NoAccessControl();
        if (config.base.access[0].validator == address(0))
            revert InvalidAccessValidator();

        // 资产基础检查
        for (uint i = 0; i < config.assets.length; i++) {
            // require(config.assets[i].token != address(0), "Invalid token");
            if (config.assets[i].amount == 0)
                revert InvalidTokenAmount(config.assets[i].token);
        }
    }

    function _transferAssets(
        address redPacket,
        RedPacketConfig[] calldata configs,
        bytes calldata permit
    ) internal {
        uint256 expectedEthValue = 0;

        (
            IPermit2.PermitBatchTransferFrom memory permitBatch,
            bytes memory signature
        ) = abi.decode(permit, (IPermit2.PermitBatchTransferFrom, bytes));

        IPermit2.SignatureTransferDetails[]
            memory transferDetails = new IPermit2.SignatureTransferDetails[](
                permitBatch.permitted.length
            );

        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = 0; j < configs[i].assets.length; j++) {
                Asset calldata asset = configs[i].assets[j];

                if (asset.assetType == AssetType.Native) {
                    expectedEthValue += asset.amount;
                } else if (asset.assetType == AssetType.ERC20) {
                    // 构建permit2 transferDetails
                    transferDetails[transferDetails.length] = IPermit2
                        .SignatureTransferDetails({
                            to: redPacket,
                            requestedAmount: asset.amount
                        });
                } else if (asset.assetType == AssetType.ERC721) {
                    // ERC721直接转账
                    IERC721(asset.token).safeTransferFrom(
                        msg.sender,
                        redPacket,
                        asset.tokenId
                    );
                } else if (asset.assetType == AssetType.ERC1155) {
                    // ERC1155直接转账
                    IERC1155(asset.token).safeTransferFrom(
                        msg.sender,
                        redPacket,
                        asset.tokenId,
                        asset.amount,
                        ""
                    );
                }
            }
        }

        if (msg.value < expectedEthValue) revert InvalidEthAmount();
        // 如果有ETH，转发给红包合约
        if (expectedEthValue > 0) {
            (bool success, ) = redPacket.call{value: expectedEthValue}("");
            if (!success) revert EthTransferFailed();
        }

        // 如果有ERC20资产，处理permit2批量转账
        if (permitBatch.permitted.length > 0) {
            PERMIT2.permitTransferFrom(
                permitBatch,
                transferDetails,
                msg.sender,
                signature
            );
        }
    }

    function _deployRedPacket() internal returns (address redPacket) {
        redPacket = address(new BeaconProxy(address(beacon), ""));

        if (!isCreator[msg.sender]) {
            creators.push(msg.sender);
            isCreator[msg.sender] = true;
        }

        redPackets[msg.sender].push(redPacket);
        redPacketCreator[redPacket] = msg.sender;

        emit RedPacketCreated(redPacket, msg.sender);
    }

    receive() external payable {}
}
