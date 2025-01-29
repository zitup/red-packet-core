// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@oz/contracts/access/Ownable.sol";
import {BeaconProxy} from "@oz/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC721} from "@oz/contracts/interfaces/IERC721.sol";
import {IERC1155} from "@oz/contracts/interfaces/IERC1155.sol";
import {ISignatureTransfer as IPermit2} from "@permit2/interfaces/ISignatureTransfer.sol";
import {IRedPacketFactory} from "./interfaces/IRedPacketFactory.sol";
import "./interfaces/IRedPacket.sol";

/// @title RedPacketFactory
/// @notice Factory contract for creating red packet proxies
contract RedPacketFactory is IRedPacketFactory, Ownable {
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

    // 协议费接收地址
    address public feeReceiver;
    // 协议费率 (基数为 10000)
    uint256 public feeRate;
    // NFT固定手续费（以wei为单位）
    uint256 public nftFlatFee;

    // 合并为一个注册表
    mapping(ComponentType => mapping(address => bool)) public isRegistered;

    // _permit: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    constructor(
        address _owner,
        address _beacon,
        address _permit,
        address _feeReceiver,
        uint256 _feeRate,
        uint256 _nftFlatFee
    ) Ownable(_owner) {
        if (_beacon == address(0)) revert ZeroBeaconAddress();
        if (_permit == address(0)) revert ZeroPermitAddress();
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver();
        if (_feeRate > 10000) revert InvalidFeeRate();

        beacon = _beacon;
        PERMIT2 = IPermit2(_permit);
        feeReceiver = _feeReceiver;
        feeRate = _feeRate;
        nftFlatFee = _nftFlatFee;
    }

    // 设置协议费配置（需要添加访问控制）
    function setFeeConfig(
        address _feeReceiver,
        uint256 _feeRate
    ) external onlyOwner {
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver();
        if (_feeRate > 10000) revert InvalidFeeRate();

        feeReceiver = _feeReceiver;
        feeRate = _feeRate;

        emit FeeConfigUpdated(_feeReceiver, _feeRate);
    }

    // 设置NFT固定手续费
    function setNFTFlatFee(uint256 _nftFlatFee) external onlyOwner {
        nftFlatFee = _nftFlatFee;
        emit NFTFlatFeeUpdated(_nftFlatFee);
    }

    // Getter functions
    /// @notice 获取创建者总数
    function getCreatorsCount() external view returns (uint256) {
        return creators.length;
    }

    /// @notice 获取指定创建者的所有红包地址
    /// @param creator 创建者地址
    function getRedPackets(
        address creator
    ) external view returns (address[] memory) {
        return redPackets[creator];
    }

    /// @notice 获取指定红包的创建者
    /// @param redPacket 红包地址
    function getRedPacketCreator(
        address redPacket
    ) external view returns (address) {
        return redPacketCreator[redPacket];
    }

    /// @notice 获取指定组件类型的所有已注册组件
    /// @param componentType 组件类型
    /// @param components 要检查的组件地址列表
    /// @return results 每个组件是否已注册的布尔值数组
    function getRegisteredComponents(
        ComponentType componentType,
        address[] calldata components
    ) external view returns (bool[] memory results) {
        results = new bool[](components.length);
        for (uint256 i = 0; i < components.length; i++) {
            results[i] = isRegistered[componentType][components[i]];
        }
    }

    function createRedPacket(
        RedPacketConfig[] calldata configs,
        bytes calldata signature
    ) public payable returns (address redPacket) {
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

    function registerComponents(
        ComponentType componentType,
        address[] calldata components
    ) external onlyOwner {
        for (uint i = 0; i < components.length; i++) {
            if (components[i] == address(0)) revert ZeroAddress();
            isRegistered[componentType][components[i]] = true;
            emit ComponentRegistered(componentType, components[i]);
        }
    }

    function unregisterComponents(
        ComponentType componentType,
        address[] calldata components
    ) external onlyOwner {
        for (uint i = 0; i < components.length; i++) {
            isRegistered[componentType][components[i]] = false;
            emit ComponentUnregistered(componentType, components[i]);
        }
    }

    // 简化验证逻辑
    function _validateRedPacketConfig(
        RedPacketConfig calldata config
    ) internal view {
        // 基础检查
        if (config.assets.length == 0) revert NoAssets();
        if (config.base.shares == 0) revert InvalidShares();
        if (config.base.access.length == 0) revert NoAccessControl();

        // 验证资产金额
        for (uint i = 0; i < config.assets.length; i++) {
            if (config.assets[i].amount == 0) {
                revert InvalidTokenAmount(config.assets[i].token);
            }
        }

        // 验证 access
        for (uint i = 0; i < config.base.access.length; i++) {
            if (
                !isRegistered[ComponentType.Access][
                    config.base.access[i].validator
                ]
            ) {
                revert InvalidComponent(
                    ComponentType.Access,
                    config.base.access[i].validator
                );
            }
        }

        // 验证 triggers
        for (uint i = 0; i < config.base.triggers.length; i++) {
            address validator = config.base.triggers[i].validator;
            if (
                validator != address(0) &&
                !isRegistered[ComponentType.Trigger][validator]
            ) {
                revert InvalidComponent(ComponentType.Trigger, validator);
            }
        }

        // 验证 distributor
        if (
            !isRegistered[ComponentType.Distributor][
                config.base.distribute.distributor
            ]
        ) {
            revert InvalidComponent(
                ComponentType.Distributor,
                config.base.distribute.distributor
            );
        }
    }

    function _transferAssets(
        address redPacket,
        RedPacketConfig[] calldata configs,
        bytes calldata permit
    ) internal {
        uint256 expectedEthValue;
        uint256 totalFee;
        (expectedEthValue, totalFee) = _handleERC20Transfers(
            redPacket,
            configs,
            permit
        );
        uint256 nftFee = _handleNFTTransfers(redPacket, configs);

        // 添加NFT固定手续费
        totalFee += nftFee;

        // 检查并转移ETH（包含手续费）
        if (msg.value < (expectedEthValue + totalFee))
            revert InvalidEthAmount(expectedEthValue + totalFee);

        // 转移完整ETH金额到红包合约
        if (expectedEthValue > 0) {
            (bool success, ) = redPacket.call{value: expectedEthValue}("");
            if (!success) revert EthTransferFailed();
        }

        // 转移ETH手续费
        if (totalFee > 0) {
            (bool success, ) = feeReceiver.call{value: totalFee}("");
            if (!success) revert EthTransferFailed();
        }
    }

    function _handleERC20Transfers(
        address redPacket,
        RedPacketConfig[] calldata configs,
        bytes calldata permit
    ) internal returns (uint256 expectedEthValue, uint256 totalFee) {
        (
            IPermit2.PermitBatchTransferFrom memory permitBatch,
            bytes memory signature
        ) = abi.decode(permit, (IPermit2.PermitBatchTransferFrom, bytes));

        IPermit2.SignatureTransferDetails[] memory transferDetails = new IPermit2.SignatureTransferDetails[](
            permitBatch.permitted.length // 为每个ERC20资产预留fee转账的空间
        );

        uint256 transferDetailsIndex = 0;

        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = 0; j < configs[i].assets.length; j++) {
                Asset calldata asset = configs[i].assets[j];

                if (asset.assetType == AssetType.Native) {
                    uint256 fee = (asset.amount * feeRate) / 10000;
                    totalFee += fee;
                    expectedEthValue += asset.amount;
                } else if (asset.assetType == AssetType.ERC20) {
                    // 转移完整金额到红包合约
                    transferDetails[transferDetailsIndex++] = IPermit2
                        .SignatureTransferDetails({
                            to: redPacket,
                            requestedAmount: asset.amount
                        });

                    // 额外转移手续费
                    uint256 fee = (asset.amount * feeRate) / 10000;
                    if (fee > 0) {
                        transferDetails[transferDetailsIndex++] = IPermit2
                            .SignatureTransferDetails({
                                to: feeReceiver,
                                requestedAmount: fee
                            });
                    }
                }
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

    function _handleNFTTransfers(
        address redPacket,
        RedPacketConfig[] calldata configs
    ) internal returns (uint256 nftFee) {
        uint256 nftCount = 0;

        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = 0; j < configs[i].assets.length; j++) {
                Asset calldata asset = configs[i].assets[j];

                if (asset.assetType == AssetType.ERC721) {
                    IERC721(asset.token).safeTransferFrom(
                        msg.sender,
                        redPacket,
                        asset.tokenId
                    );
                    nftCount++;
                } else if (asset.assetType == AssetType.ERC1155) {
                    IERC1155(asset.token).safeTransferFrom(
                        msg.sender,
                        redPacket,
                        asset.tokenId,
                        asset.amount,
                        ""
                    );
                    nftCount++;
                }
            }
        }

        return nftCount * nftFlatFee;
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
