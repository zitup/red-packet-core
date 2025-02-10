// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {RedPacketFactory} from "../src/RedPacketFactory.sol";
import {IRedPacketFactory} from "../src/interfaces/IRedPacketFactory.sol";
import {RedPacket} from "../src/RedPacket.sol";
import {UpgradeableBeacon} from "@oz/contracts/proxy/beacon/UpgradeableBeacon.sol";

// Access
import {CodeAccess} from "../src/access/CodeAccess/CodeAccess.sol";
import {Groth16Verifier} from "../src/access/CodeAccess/Verifier.sol";
import {HolderAccess} from "../src/access/HolderAccess.sol";
import {LuckyDrawAccess} from "../src/access/LuckyDrawAccess.sol";
import {StateAccess} from "../src/access/StateAccess.sol";
import {WhitelistAccess} from "../src/access/WhitelistAccess.sol";

// Triggers
import {PriceTrigger} from "../src/trigger/PriceTrigger.sol";
import {StateTrigger} from "../src/trigger/StateTrigger.sol";

// Distributors
import {FixedDistributor} from "../src/distributor/FixedDistributor.sol";
import {RandomDistributor} from "../src/distributor/RandomDistributor.sol";

// Mock Contracts
import {Permit2 as MockPermit2} from "../src/mocks/MockPermit2/Permit2.sol";
import {MockAggregatorV3} from "../src/mocks/MockAggregatorV3.sol";
import {MockMulticall3} from "../src/mocks/MockMulticall3.sol";

contract Deploy is Script {
    // 各链上的 Permit2 地址
    mapping(uint256 => address) internal PERMIT2;
    // 各链上的 Chainlink sequencer 地址
    mapping(uint256 => address) internal SEQUENCER;
    // 各链上的 ETH/USD 价格预言机地址
    mapping(uint256 => address) internal ETH_USD_FEED;

    // 存储部署的合约地址
    RedPacketFactory public factory;
    UpgradeableBeacon public beacon;
    RedPacket public implementation;

    // Access 合约
    Groth16Verifier public verifier;
    CodeAccess public codeAccess;
    HolderAccess public holderAccess;
    WhitelistAccess public whitelistAccess;
    LuckyDrawAccess public luckyDrawAccess;
    StateAccess public stateAccess;

    // Trigger 合约
    PriceTrigger public priceTrigger;
    StateTrigger public stateTrigger;

    // Distributor 合约
    FixedDistributor public fixedDistributor;
    RandomDistributor public randomDistributor;

    // Create2 salt
    bytes32 constant FACTORY_SALT = bytes32(uint256(1));
    bytes32 constant BEACON_SALT = bytes32(uint256(2));
    bytes32 constant IMPLEMENTATION_SALT = bytes32(uint256(3));

    constructor() {
        // Permit2 addresses
        PERMIT2[31337] = address(0); // Anvil - 将在部署时设置
        PERMIT2[11155111] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Sepolia
        PERMIT2[8453] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Base
        PERMIT2[56] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // BSC
        PERMIT2[42161] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Arbitrum
        PERMIT2[10] = 0x000000000022D473030F116dDEE9F6B43aC78BA3; // Optimism

        // Chainlink sequencer addresses
        SEQUENCER[8453] = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433; // Base
        SEQUENCER[42161] = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D; // Arbitrum
        SEQUENCER[10] = 0x371EAD81c9102C9BF4874A9075FFFf170F2Ee389; // Optimism

        // ETH/USD Price Feed addresses
        ETH_USD_FEED[31337] = address(0); // Anvil - 将在部署时设置
        ETH_USD_FEED[11155111] = 0x694AA1769357215DE4FAC081bf1f309aDC325306; // Sepolia
        ETH_USD_FEED[8453] = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70; // Base
        ETH_USD_FEED[56] = 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e; // BSC
        ETH_USD_FEED[42161] = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; // Arbitrum
        ETH_USD_FEED[10] = 0x13e3Ee699D1909E989722E753853AE30b17e08c5; // Optimism
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        deployContracts();
        registerComponents();
        logAddresses();

        vm.stopBroadcast();
    }

    function deployContracts() internal {
        // 部署配置
        address feeReceiver = vm.envAddress("FEE_RECEIVER");

        // 1. 部署 Access
        verifier = new Groth16Verifier{salt: bytes32(uint256(1))}();
        codeAccess = new CodeAccess{salt: bytes32(uint256(1))}(
            address(verifier)
        );
        holderAccess = new HolderAccess{salt: bytes32(uint256(2))}();
        whitelistAccess = new WhitelistAccess{salt: bytes32(uint256(3))}();
        luckyDrawAccess = new LuckyDrawAccess{salt: bytes32(uint256(4))}();
        stateAccess = new StateAccess{salt: bytes32(uint256(5))}();

        // 2. 部署 Triggers
        priceTrigger = new PriceTrigger{salt: bytes32(uint256(6))}(
            SEQUENCER[block.chainid]
        );
        stateTrigger = new StateTrigger{salt: bytes32(uint256(7))}();

        // 3. 部署 Distributors
        fixedDistributor = new FixedDistributor{salt: bytes32(uint256(8))}();
        randomDistributor = new RandomDistributor{salt: bytes32(uint256(9))}();

        // 4. 使用 create2 部署红包实现合约
        bytes32 implementationSalt = keccak256(
            abi.encodePacked(IMPLEMENTATION_SALT)
        );
        implementation = new RedPacket{salt: implementationSalt}();

        // 5. 使用 create2 部署 Beacon
        bytes32 beaconSalt = keccak256(abi.encodePacked(BEACON_SALT));
        beacon = new UpgradeableBeacon{salt: beaconSalt}(
            address(implementation),
            msg.sender
        );

        // 如果是本地网络，部署 Mock Permit2 和 Mock Price Feed
        if (block.chainid == 31337) {
            MockPermit2 mockPermit2 = new MockPermit2{
                salt: bytes32(uint256(4))
            }();
            PERMIT2[block.chainid] = address(mockPermit2);

            MockAggregatorV3 mockPriceFeed = new MockAggregatorV3{
                salt: bytes32(uint256(5))
            }();
            ETH_USD_FEED[block.chainid] = address(mockPriceFeed);

            MockMulticall3 mockMulticall3 = new MockMulticall3{
                salt: bytes32(uint256(6))
            }();
        }

        // 6. 使用 create2 部署工厂合约
        bytes32 factorySalt = keccak256(abi.encodePacked(FACTORY_SALT));
        factory = new RedPacketFactory{salt: factorySalt}(
            msg.sender,
            address(beacon),
            PERMIT2[block.chainid],
            feeReceiver,
            ETH_USD_FEED[block.chainid]
        );
    }

    function registerComponents() internal {
        // 注册 Access
        address[] memory accesses = new address[](6);
        accesses[0] = address(codeAccess);
        accesses[1] = address(holderAccess);
        accesses[2] = address(whitelistAccess);
        accesses[3] = address(luckyDrawAccess);
        accesses[4] = address(stateAccess);
        accesses[5] = address(verifier);
        factory.registerComponents(
            IRedPacketFactory.ComponentType.Access,
            accesses
        );

        // 注册 Triggers
        address[] memory triggers = new address[](2);
        triggers[0] = address(priceTrigger);
        triggers[1] = address(stateTrigger);
        factory.registerComponents(
            IRedPacketFactory.ComponentType.Trigger,
            triggers
        );

        // 注册 Distributors
        address[] memory distributors = new address[](2);
        distributors[0] = address(randomDistributor);
        distributors[1] = address(fixedDistributor);
        factory.registerComponents(
            IRedPacketFactory.ComponentType.Distributor,
            distributors
        );
    }

    function logAddresses() internal view {
        console.log("Deployed to chain:", block.chainid);
        console.log("\nCore contracts:");
        console.log("Implementation:", address(implementation));
        console.log("Beacon:", address(beacon));
        console.log("Factory:", address(factory));
        console.log("Permit2:", PERMIT2[block.chainid]);
        if (block.chainid == 31337) {
            console.log("ETH/USD Feed:", ETH_USD_FEED[block.chainid]);
        }

        console.log("\nAccess:");
        console.log("CodeAccess:", address(codeAccess));
        console.log("HolderAccess:", address(holderAccess));
        console.log("WhitelistAccess:", address(whitelistAccess));
        console.log("LuckyDrawAccess:", address(luckyDrawAccess));
        console.log("StateAccess:", address(stateAccess));

        console.log("\nTriggers:");
        console.log("StateTrigger:", address(stateTrigger));
        console.log("PriceTrigger:", address(priceTrigger));

        console.log("\nDistributors:");
        console.log("RandomDistributor:", address(randomDistributor));
        console.log("FixedDistributor:", address(fixedDistributor));
    }
}
