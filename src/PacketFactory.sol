// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Ownable} from "@oz/contracts/access/Ownable.sol";
import {BeaconProxy} from "@oz/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC721} from "@oz/contracts/interfaces/IERC721.sol";
import {IERC1155} from "@oz/contracts/interfaces/IERC1155.sol";
import {ISignatureTransfer as IPermit2} from "@permit2/interfaces/ISignatureTransfer.sol";
import {IPacketFactory} from "./interfaces/IPacketFactory.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import "./interfaces/IPacket.sol";

/// @title PacketFactory
/// @notice Factory contract for creating packet proxies
contract PacketFactory is IPacketFactory, Ownable {
    // Beacon合约地址
    address public immutable beacon;

    IPermit2 public immutable PERMIT2;

    // ETH/USD 价格预言机
    IAggregatorV3 public immutable ETH_USD_FEED;

    // 每份红包的费用分母 (10表示0.1U, 100表示0.01U)
    uint256 public feeShareDenominator = 10;

    // 创建者数量
    uint256 public creatorsCount;
    // 所有红包
    address[] public packets;
    // 创建者的红包索引映射
    mapping(address => uint256[]) private creatorPacketIndices;

    // 协议费接收地址
    address public feeReceiver;

    // 合并为一个注册表
    mapping(ComponentType => mapping(address => bool)) public isRegistered;

    // _permit: 0x000000000022D473030F116dDEE9F6B43aC78BA3
    constructor(
        address _owner,
        address _beacon,
        address _permit,
        address _feeReceiver,
        address _ethUsdFeed
    ) Ownable(_owner) {
        if (_beacon == address(0)) revert ZeroBeaconAddress();
        if (_permit == address(0)) revert ZeroPermitAddress();
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver();
        if (_ethUsdFeed == address(0)) revert InvalidPriceFeed();

        beacon = _beacon;
        PERMIT2 = IPermit2(_permit);
        feeReceiver = _feeReceiver;
        ETH_USD_FEED = IAggregatorV3(_ethUsdFeed);
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

    /// @notice 计算指定份数的手续费（以ETH为单位）
    /// @param shares 红包份数
    /// @return feeInETH 手续费（以ETH为单位）
    /// @return feeInUSD 手续费（以USD为单位，6位小数）
    /// @return ethPrice ETH/USD价格（8位小数）
    function calculateFee(
        uint256 shares
    )
        external
        view
        returns (uint256 feeInETH, uint256 feeInUSD, int256 ethPrice)
    {
        return _calculateFee(shares);
    }

    // 设置协议费接收地址
    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        if (_feeReceiver == address(0)) revert InvalidFeeReceiver();
        feeReceiver = _feeReceiver;
        emit FeeReceiverUpdated(_feeReceiver);
    }

    function setFeeShareDenominator(uint256 _denominator) external onlyOwner {
        if (_denominator == 0) revert InvalidFeeConfig();
        feeShareDenominator = _denominator;
        emit FeeDenominatorUpdated(_denominator);
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

    function createPacket(
        PacketConfig[] calldata configs,
        bytes calldata signature
    ) public payable returns (address packet) {
        if (configs.length == 0) revert EmptyConfigs();

        // # 1. 验证配置
        uint256 totalShares;
        for (uint i = 0; i < configs.length; i++) {
            _validatePacketConfig(configs[i]);
            totalShares += configs[i].base.shares;
        }

        // # 2. 部署红包合约
        packet = _deployPacket();

        // # 3. 处理资产转移
        _transferAssets(packet, configs, signature, totalShares);

        // # 4. 初始化红包合约
        IPacket(packet).initialize(configs, msg.sender);
    }

    // 简化验证逻辑
    function _validatePacketConfig(PacketConfig calldata config) internal view {
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
        PacketConfig[] calldata configs,
        bytes calldata permit,
        uint256 totalShares
    ) internal {
        uint256 expectedEthValue;
        (expectedEthValue) = _handleERC20Transfers(packet, configs, permit);

        _handleNFTTransfers(packet, configs);

        // 计算基于份数的手续费
        (uint256 totalFee, , ) = _calculateFee(totalShares);

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
        PacketConfig[] calldata configs,
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

        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = 0; j < configs[i].assets.length; j++) {
                Asset calldata asset = configs[i].assets[j];

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
        address packet,
        PacketConfig[] calldata configs
    ) internal {
        for (uint256 i = 0; i < configs.length; i++) {
            for (uint256 j = 0; j < configs[i].assets.length; j++) {
                Asset calldata asset = configs[i].assets[j];

                if (asset.assetType == AssetType.ERC721) {
                    IERC721(asset.token).safeTransferFrom(
                        msg.sender,
                        packet,
                        asset.tokenId
                    );
                } else if (asset.assetType == AssetType.ERC1155) {
                    IERC1155(asset.token).safeTransferFrom(
                        msg.sender,
                        packet,
                        asset.tokenId,
                        asset.amount,
                        ""
                    );
                }
            }
        }
    }

    function _calculateFee(
        uint256 shares
    )
        internal
        view
        returns (uint256 feeInETH, uint256 feeInUSD, int256 ethPrice)
    {
        // 获取最新的ETH/USD价格
        (, ethPrice, , , ) = ETH_USD_FEED.latestRoundData();
        if (ethPrice <= 0) revert InvalidPrice();

        // 计算以USD计价的总费用（每份0.1U）
        // 例如：10份 * (1/10)U = 1U
        feeInUSD = shares * (1e6 / feeShareDenominator); // 结果保持6位小数

        // 将USD费用转换为ETH
        // 1. 将ETH价格转换为1U对应的ETH数量（1/price）
        // 2. 将这个比例应用到我们的feeInUSD上
        // ethPrice是ETH/USD价格，带有8位小数
        uint256 priceScaled = uint256(ethPrice) * 1e10; // 8位小数 -> 18位小数
        uint256 oneUsdInEth = 1e36 / priceScaled; // 1e18 * 1e18 / priceScaled，得到1U对应的ETH数量（18位小数）
        feeInETH = (feeInUSD * oneUsdInEth) / 1e6; // feeInUSD（6位小数）* oneUsdInEth（18位小数）/ 1e6 = ETH数量（18位小数）
    }

    receive() external payable {}
}
