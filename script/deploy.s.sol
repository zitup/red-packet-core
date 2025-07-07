// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {PacketFactory} from "../src/PacketFactory.sol";
import {Packet} from "../src/Packet.sol";
import {UpgradeableBeacon} from "@oz/contracts/proxy/beacon/UpgradeableBeacon.sol";

// Mock Contracts
import {Permit2 as MockPermit2} from "../src/mocks/MockPermit2/Permit2.sol";
import {MockMulticall3} from "../src/mocks/MockMulticall3.sol";

contract Deploy is Script {
    // 各链上的 Permit2 地址
    mapping(uint256 => address) internal PERMIT2;

    // 存储部署的合约地址
    PacketFactory public factory;
    UpgradeableBeacon public beacon;
    Packet public implementation;

    // Create2 salt
    bytes32 constant FACTORY_SALT = bytes32(uint256(1));
    bytes32 constant BEACON_SALT = bytes32(uint256(2));
    bytes32 constant IMPLEMENTATION_SALT = bytes32(uint256(3));

    constructor() {
        // Permit2 addresses
        PERMIT2[31337] = address(0); // Anvil - 将在部署时设置
        // PERMIT2[11155111] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Sepolia
        // PERMIT2[8453] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Base
        // PERMIT2[56] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // BSC
        // PERMIT2[42161] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Arbitrum
        // PERMIT2[10] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Optimism
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployContracts();
        logAddresses();

        vm.stopBroadcast();
    }

    function deployContracts() internal {
        // 部署配置
        address feeReceiver = vm.envAddress("FEE_RECEIVER");

        // 1. 使用 create2 部署红包实现合约
        bytes32 implementationSalt = keccak256(
            abi.encodePacked(IMPLEMENTATION_SALT)
        );
        implementation = new Packet{salt: implementationSalt}();

        // 2. 使用 create2 部署 Beacon
        bytes32 beaconSalt = keccak256(abi.encodePacked(BEACON_SALT));
        beacon = new UpgradeableBeacon{salt: beaconSalt}(
            address(implementation),
            msg.sender
        );

        // 如果是本地网络，部署 Mock Permit2 和 Mock Multicall
        if (block.chainid == 31337) {
            MockPermit2 mockPermit2 = new MockPermit2{
                salt: bytes32(uint256(4))
            }();
            PERMIT2[block.chainid] = address(mockPermit2);

            MockMulticall3 mockMulticall3 = new MockMulticall3{
                salt: bytes32(uint256(6))
            }();
        }

        // 3. 使用 create2 部署工厂合约
        bytes32 factorySalt = keccak256(abi.encodePacked(FACTORY_SALT));
        factory = new PacketFactory{salt: factorySalt}(
            msg.sender,
            address(beacon),
            PERMIT2[block.chainid],
            feeReceiver
        );
    }

    function logAddresses() internal view {
        console.log("Deployed to chain:", block.chainid);
        console.log("\nCore contracts:");
        console.log("Implementation:", address(implementation));
        console.log("Beacon:", address(beacon));
        console.log("Factory:", address(factory));
        console.log("Permit2:", PERMIT2[block.chainid]);
    }
}
