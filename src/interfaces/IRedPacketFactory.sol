// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "./IRedPacket.sol";

interface IRedPacketFactory {
    // 使用一个枚举来标识组件类型
    enum ComponentType {
        Access,
        Trigger,
        Distributor
    }

    /// Errors
    error EmptyConfigs();
    error ZeroBeaconAddress();
    error ZeroPermitAddress();
    error NoAssets();
    error InvalidShares();
    error InvalidDistributor();
    error NoAccessControl();
    error InvalidAccessValidator();
    error InvalidTokenAmount(address);
    error InvalidEthAmount(uint256 expectedEthValue);
    error EthTransferFailed();
    error InvalidFeeRate();
    error InvalidFeeReceiver();
    error InvalidComponent(ComponentType componentType, address component);
    error ZeroAddress();

    /// Events
    event RedPacketCreated(
        address indexed redPacket, // 红包合约地址
        address indexed creator // 创建者
    );

    event FeeConfigUpdated(address indexed feeReceiver, uint256 feeRate);
    event NFTFlatFeeUpdated(uint256 nftFlatFee);
    event ComponentRegistered(
        ComponentType indexed componentType,
        address indexed component
    );
    event ComponentUnregistered(
        ComponentType indexed componentType,
        address indexed component
    );

    function beacon() external view returns (address); // Beacon地址

    function redPackets(
        address user,
        uint256 index
    ) external view returns (address);

    function feeReceiver() external view returns (address);

    function feeRate() external view returns (uint256);

    function setFeeConfig(address _feeReceiver, uint256 _feeRate) external;

    function createRedPacket(
        RedPacketConfig[] calldata configs,
        bytes calldata permit
    ) external payable returns (address redPacket); // 返回红包合约地址
}
