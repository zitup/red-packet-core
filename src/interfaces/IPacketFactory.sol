// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "./types.sol";

interface IPacketFactory {
    event PacketCreated(address indexed packet, address indexed creator);
    event FeeReceiverUpdated(address indexed feeReceiver);

    error ZeroBeaconAddress();
    error ZeroPermitAddress();
    error InvalidFeeReceiver();
    error ZeroAddress();
    error EmptyConfigs();
    error NoAssets();
    error InvalidShares();
    error NoAccessControl();
    error InvalidTokenAmount(address token);
    error InvalidEthAmount(uint256 required);
    error EthTransferFailed();
    error InvalidFeeConfig();

    function beacon() external view returns (address); // Beacon地址

    function feeReceiver() external view returns (address);

    function createPacket(
        PacketConfig[] calldata configs,
        bytes calldata permit
    ) external payable returns (address packet); // 返回红包合约地址

    /// @notice 计算指定份数的手续费（以ETH为单位）
    /// @param shares 红包份数
    /// @return feeInETH 手续费（以ETH为单位）
    function calculateFee(
        uint256 shares
    ) external view returns (uint256 feeInETH);
}
