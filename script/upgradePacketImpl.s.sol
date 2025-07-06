// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Packet} from "../src/Packet.sol";
import {UpgradeableBeacon} from "@oz/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract UpgradePacketImpl is Script {
    // Create2 salt for deterministic deployment
    bytes32 constant IMPLEMENTATION_SALT = bytes32(uint256(3));

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address beaconAddress = vm.envAddress("BEACON_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation with create2
        bytes32 implementationSalt = keccak256(
            abi.encodePacked(IMPLEMENTATION_SALT)
        );
        Packet implementation = new Packet{salt: implementationSalt}();
        console.log("New implementation deployed at:", address(implementation));

        // Upgrade beacon to point to new implementation
        UpgradeableBeacon beacon = UpgradeableBeacon(beaconAddress);
        beacon.upgradeTo(address(implementation));
        console.log("Beacon upgraded to new implementation");

        vm.stopBroadcast();
    }
}
