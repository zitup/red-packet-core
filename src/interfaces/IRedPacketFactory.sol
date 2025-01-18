// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "./IRedPacket.sol";

interface IRedPacketFactory {
    /// Errors
    error EmptyConfigs();
    error ZeroBeaconAddress();
    error NoAssets();
    error InvalidShares();
    error InvalidDistributor();
    error NoAccessControl();
    error InvalidAccessValidator();
    error InvalidTokenAmount(address);
    error InvalidEthAmount();
    error EthTransferFailed();

    /// Events
    event RedPacketCreated(
        address indexed redPacket, // 红包合约地址
        address indexed creator // 创建者
    );

    function beacon() external view returns (address); // Beacon地址

    function redPackets(
        address user,
        uint256 index
    ) external view returns (address);

    function createRedPacket(
        RedPacketConfig[] calldata configs,
        bytes calldata permit
    ) external returns (address redPacket); // 返回红包合约地址
}
