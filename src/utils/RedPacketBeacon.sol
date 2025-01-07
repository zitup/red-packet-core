// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import "@oz/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title RedPacketBeacon
 * @dev This contract manages the implementation address for all red packet proxy contracts.
 * It inherits from OpenZeppelin's UpgradeableBeacon and is designed to be owned by a 
 * multisig wallet or EOA for secure implementation upgrades.
 *
 * The beacon pattern is chosen because:
 * 1. It reduces deployment costs as all proxies share the same beacon
 * 2. It simplifies upgrades as changing the beacon's implementation updates all proxies
 * 3. It provides a centralized point of control for all red packet implementations
 *
 * Usage:
 *
    // Deploy implementation
    RedPacketImplementation implementation = new RedPacketImplementation();
    // Deploy beacon with implementation and multisig as owner
    RedPacketBeacon beacon = new RedPacketBeacon(
      address(implementation),
      multiSigAddress
    );
    // Update implementation (only owner)
    beacon.upgradeTo(newImplementationAddress);
*/
contract RedPacketBeacon is UpgradeableBeacon {
    /**
     * @dev Emitted when the beacon is deployed
     * @param implementation The initial implementation address
     * @param owner The owner address (typically a multisig wallet)
     */
    event BeaconDeployed(address indexed implementation, address indexed owner);

    /**
     * @dev Constructor that sets the initial implementation and transfers ownership
     * @param implementation_ The address of the initial implementation contract
     * @param owner_ The address that will own this beacon (should be a multisig wallet)
     */
    constructor(
        address implementation_,
        address owner_
    ) UpgradeableBeacon(implementation_, owner_) {
        require(owner_ != address(0), "RPB: zero owner address");

        emit BeaconDeployed(implementation_, owner_);
    }

    /**
     * @dev Returns the current implementation address and beacon owner
     * @return implementation The current implementation address
     * @return owner The current beacon owner
     */
    function getBeaconInfo() external view returns (address, address) {
        return (implementation(), owner());
    }
}
