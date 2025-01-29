// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";

// import {RedPacketFactory} from "../src/RedPacketFactory.sol";
// import {MockERC20} from "./MockERC20.t.sol";
// import {IRedPacketFactory} from "../src/interfaces/IRedPacketFactory.sol";
// import {ISignatureTransfer} from "@permit2/interfaces/ISignatureTransfer.sol";
// import {Asset, AssetType, BaseConfig, RedPacketConfig} from "../src/interfaces/types.sol";
// import {AccessConfig} from "../src/interfaces/IAccess.sol";
// import {TriggerConfig} from "../src/interfaces/ITrigger.sol";
// import {DistributeConfig} from "../src/interfaces/IDistributor.sol";
import {console} from "forge-std/console.sol";

contract RedPacketFactoryTest is Test {
    // RedPacketFactory factory;
    // MockERC20 token;
    // address beacon = makeAddr("beacon");
    // address permit2 = makeAddr("permit2");
    // address feeReceiver = makeAddr("feeReceiver");
    address user = makeAddr("user");

    // address accessValidator = makeAddr("accessValidator");
    // address distributor = makeAddr("distributor");

    function setUp() public {
        // // Deploy factory
        // factory = new RedPacketFactory(
        //     beacon,
        //     permit2,
        //     feeReceiver,
        //     100, // 1% fee rate
        //     0.01 ether // NFT flat fee
        // );
        // // Deploy mock token
        // token = new MockERC20("Test Token", "TEST");
        // // Register components
        // address[] memory components = new address[](1);
        // // Register access validator
        // components[0] = accessValidator;
        // factory.registerComponents(
        //     IRedPacketFactory.ComponentType.Access,
        //     components
        // );
        // // Register distributor
        // components[0] = distributor;
        // factory.registerComponents(
        //     IRedPacketFactory.ComponentType.Distributor,
        //     components
        // );
        // vm.deal(user, 100 ether);
    }

    // function test_createRedPacket() public {
    //     vm.startPrank(user);

    //     // Prepare config data
    //     Asset[] memory assets = new Asset[](1);
    //     assets[0] = Asset({
    //         assetType: AssetType.Native,
    //         token: address(0),
    //         amount: 1 ether,
    //         tokenId: 0
    //     });

    //     AccessConfig[] memory accessRules = new AccessConfig[](1);
    //     accessRules[0] = AccessConfig({validator: accessValidator, data: ""});

    //     TriggerConfig[] memory triggerRules = new TriggerConfig[](1);
    //     triggerRules[0] = TriggerConfig({validator: address(0), data: ""});

    //     DistributeConfig memory distributeConfig = DistributeConfig({
    //         distributor: distributor,
    //         data: ""
    //     });

    //     BaseConfig memory baseConfig = BaseConfig({
    //         name: "Test Red Packet",
    //         message: "Happy Testing!",
    //         startTime: block.timestamp,
    //         durationTime: 1 days,
    //         shares: 100,
    //         access: accessRules,
    //         triggers: triggerRules,
    //         distribute: distributeConfig
    //     });

    //     RedPacketConfig[] memory configs = new RedPacketConfig[](1);
    //     configs[0] = RedPacketConfig({base: baseConfig, assets: assets});

    //     // Create red packet
    //     address redPacket = factory.createRedPacket{value: 1.01 ether}(
    //         configs,
    //         ""
    //     );

    //     // Verify red packet creation
    //     assertTrue(redPacket != address(0), "Red packet not created");
    //     assertEq(factory.redPacketCreator(redPacket), user, "Wrong creator");

    //     vm.stopPrank();
    // }

    function test_createRedPacket_withExactCalldata() public {
        bytes
            memory calldata_ = hex"ef6f79970000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e00000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000679a5a05000000000000000000000000000000000000000000000000000000000001518000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000000000000000000000000000001310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000004311ea0a74a3f6ccb1467a829f686b9e6b66b7390000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e0e90418692d4bcc70658a42c5b287e702796940000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000222d377f7ba38567492e4d253c69a0ec237366e6000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000001c0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000679a68180000000000000000000000000000000000000000000000000000000000000002000000000000000000000000222d377f7ba38567492e4d253c69a0ec237366e600000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000222d377f7ba38567492e4d253c69a0ec237366e600000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000041be649ac7dad8164ae39e5de3a633b67703149c9bdcf86cc67ce1215087e90bbf5934fc3d37b8c72b6783364c1ea9ab8eab5402805cec4c404b4a004fa51f57e51c00000000000000000000000000000000000000000000000000000000000000";

        vm.startPrank(user);
        vm.deal(user, 100 ether);

        // // Register actual components from calldata
        // address[] memory components = new address[](1);

        // // Register access validator from calldata
        // components[0] = 0x2279B7A0A67DB372996a5FaB50D91eAa73d2eBE6;
        // factory.registerComponents(
        //     IRedPacketFactory.ComponentType.Access,
        //     components
        // );

        // // Register distributor from calldata
        // components[0] = 0x9A9f2CCfdE556A7E9Ff0848998AA4a0CFD8863AE;
        // factory.registerComponents(
        //     IRedPacketFactory.ComponentType.Distributor,
        //     components
        // );

        // Call function with exact calldata
        (bool success, bytes memory result) = address(
            0x752b5a28E1BDFd6b35ad4508299bCDC1903FDC1C
        ).call(calldata_);
        console.log("success", success);
        console.logBytes(result);
        require(success, "Call failed");

        // Decode result to get redPacket address
        // address redPacket = abi.decode(result, (address));

        // Verify red packet creation
        // assertTrue(redPacket != address(0), "Red packet not created");
        // assertEq(factory.redPacketCreator(redPacket), user, "Wrong creator");

        vm.stopPrank();
    }
}
