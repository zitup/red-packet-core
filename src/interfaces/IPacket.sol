// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "./ITrigger.sol";
import "./IAccess.sol";
import "./IDistributor.sol";
import "./types.sol";

interface IPacket {
    struct NFTInfo {
        address token;
        uint256 tokenId;
    }

    struct ERC1155Info {
        address token;
        uint256 tokenId;
    }

    /// errors
    error NotFactory();
    error NotCreator();
    error NotStarted();
    error NotExpired();
    error Expired();
    error AlreadyClaimed();
    error NoRemainingShares();
    error AccessDenied(address);
    error TriggerConditionNotMet(address);
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
        bytes[] calldata accessProofs
    ) external returns (bool);

    function claimAll(bytes[][] calldata accessProofs) external;

    function isExpired() external view returns (bool);
}
