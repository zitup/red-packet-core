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
    event Claimed(
        address indexed claimer,
        uint256 indexed packetIndex,
        DistributeResult[] result
    );

    event ClaimAll(address indexed claimer, uint256 totalPackets);

    function creator() external view returns (address);

    function initialize(
        PacketConfig[] calldata config,
        address _creator
    ) external;

    function getPacketInfo()
        external
        view
        returns (PacketInfo memory packetInfo);

    function claim(
        uint256 packetIndex,
        bytes32[] calldata merkleProof
    ) external returns (bool);

    function claimAll(bytes32[][] calldata accessProofs) external;

    function isExpired() external view returns (bool);

    function withdrawAllAssets(
        address[] calldata tokens,
        address recipient
    ) external;
}
