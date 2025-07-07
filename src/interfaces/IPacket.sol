// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "./types.sol";

interface IPacket {
    /// errors
    error NotFactory();
    error NotCreator();
    error NotStarted();
    error NotExpired();
    error Expired();
    error AlreadyClaimed();
    error NoRemainingShares();
    error AccessDenied();
    error EthTransferFailed();
    /// events
    event Claimed(address indexed claimer, DistributeResult[] result);

    function creator() external view returns (address);

    function initialize(
        PacketConfig calldata config,
        address _creator
    ) external;

    function getPacketInfo()
        external
        view
        returns (PacketInfo memory packetInfo);

    function claim(bytes32[] calldata merkleProof) external returns (bool);

    function isExpired() external view returns (bool);

    function withdrawAllAssets(
        address[] calldata tokens,
        address recipient
    ) external;
}
