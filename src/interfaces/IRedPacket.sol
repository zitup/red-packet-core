// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "./ITrigger.sol";
import "./IAccess.sol";
import "./IDistributor.sol";
import "./types.sol";

interface IRedPacket {
    /// errors
    error NotFactory();
    error NotStarted();
    error Expired();
    error AlreadyClaimed();
    error NoRemainingShares();
    error AccessDenied(address);
    error TriggerConditionNotMet(address);
    error TransferFailed();

    /// events
    event Claimed(
        address indexed claimer,
        uint256 indexed redPacketIndex,
        IDistributor.DistributeResult[] result
    );

    function initialize(
        RedPacketConfig[] calldata config,
        address _creator
    ) external;
}
