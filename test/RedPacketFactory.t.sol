// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Deploy} from "../script/deploy.s.sol";
import {RedPacketFactory} from "../src/RedPacketFactory.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IRedPacketFactory} from "../src/interfaces/IRedPacketFactory.sol";
import {ISignatureTransfer} from "@permit2/interfaces/ISignatureTransfer.sol";
import {Asset, AssetType, BaseConfig, RedPacketConfig} from "../src/interfaces/types.sol";
import {AccessConfig} from "../src/interfaces/IAccess.sol";
import {TriggerConfig} from "../src/interfaces/ITrigger.sol";
import {DistributeConfig} from "../src/interfaces/IDistributor.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";

contract RedPacketFactoryTest is Deploy, Test {
    address user;
    address user2;
    MockERC20 mockToken;

    function setUp() public {
        // 设置测试账户
        user = makeAddr("user");
        user2 = makeAddr("user2");
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);

        // 设置环境变量
        vm.setEnv("PRIVATE_KEY", "1");
        vm.setEnv("FEE_RECEIVER", vm.toString(makeAddr("feeReceiver")));

        // 部署所有合约
        deployContracts();
        vm.startPrank(factory.owner());
        registerComponents();
        vm.stopPrank();

        // 部署测试代币
        mockToken = new MockERC20("Test Token", "TEST");
        mockToken.mint(user, 1000 ether);
        mockToken.mint(user2, 1000 ether);
    }

    function test_constructor() public {
        assertEq(factory.beacon(), address(beacon));
        assertEq(address(factory.PERMIT2()), PERMIT2[block.chainid]);
        assertEq(factory.feeShareDenominator(), 10); // 默认值为10，表示每份0.1U
        assertEq(factory.owner(), msg.sender);
    }

    function test_setFeeConfig() public {
        address newFeeReceiver = makeAddr("newFeeReceiver");
        uint256 newDenominator = 20; // 0.05U per share

        // 非 owner 不能设置
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.setFeeReceiver(newFeeReceiver);

        // owner 可以设置
        vm.startPrank(factory.owner());
        factory.setFeeReceiver(newFeeReceiver);
        factory.setFeeShareDenominator(newDenominator);
        vm.stopPrank();

        assertEq(factory.feeReceiver(), newFeeReceiver);
        assertEq(factory.feeShareDenominator(), newDenominator);

        // 不能设置零地址
        vm.prank(factory.owner());
        vm.expectRevert(IRedPacketFactory.InvalidFeeReceiver.selector);
        factory.setFeeReceiver(address(0));

        // 不能设置零分母
        vm.prank(factory.owner());
        vm.expectRevert(IRedPacketFactory.InvalidFeeConfig.selector);
        factory.setFeeShareDenominator(0);
    }

    function test_calculateFee() public {
        // 设置ETH价格为2000U
        int256 ethPrice = 2000e8; // 8位小数
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, ethPrice, 0, 0, 0)
        );

        // 测试100份红包的费用
        (uint256 feeInETH, uint256 feeInUSD, int256 returnedEthPrice) = factory
            .calculateFee(100);

        // 验证返回的ETH价格
        assertEq(returnedEthPrice, ethPrice);

        // 验证USD费用：100份 * 0.1U = 10U (带6位小数)
        assertEq(feeInUSD, 10e6);

        // 验证ETH费用：10U / 2000U/ETH = 0.005 ETH
        assertEq(feeInETH, 0.005 ether);

        // 测试0份红包
        (feeInETH, feeInUSD, ) = factory.calculateFee(0);
        assertEq(feeInETH, 0);
        assertEq(feeInUSD, 0);

        // 测试大数量份数
        uint256 largeShares = 1000000;
        (feeInETH, feeInUSD, ) = factory.calculateFee(largeShares);
        // 1000000份 * 0.1U = 100000U
        assertEq(feeInUSD, 100000e6);
        // 100000U / 2000U/ETH = 50 ETH
        assertEq(feeInETH, 50 ether);

        // 测试负价格情况
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, -1, 0, 0, 0)
        );
        vm.expectRevert(IRedPacketFactory.InvalidPrice.selector);
        factory.calculateFee(100);
    }

    function test_createRedPacket_errors() public {
        vm.startPrank(user);

        // 准备基础配置
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 1 ether,
            tokenId: 0
        });

        AccessConfig[] memory accessRules = new AccessConfig[](1);
        accessRules[0] = AccessConfig({
            validator: address(codeAccess),
            data: ""
        });

        BaseConfig memory baseConfig = BaseConfig({
            name: "Test Red Packet",
            message: "Happy Testing!",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 100,
            access: accessRules,
            triggers: new TriggerConfig[](0),
            distribute: DistributeConfig({
                distributor: address(fixedDistributor),
                data: ""
            })
        });

        RedPacketConfig[] memory configs = new RedPacketConfig[](1);
        configs[0] = RedPacketConfig({base: baseConfig, assets: assets});

        // 设置ETH价格
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        // 测试ETH金额不足
        vm.expectRevert(
            abi.encodeWithSelector(
                IRedPacketFactory.InvalidEthAmount.selector,
                1.005 ether
            )
        );
        factory.createRedPacket{value: 1 ether}(configs, "");

        // 测试空配置数组
        vm.expectRevert(IRedPacketFactory.EmptyConfigs.selector);
        factory.createRedPacket{value: 1 ether}(new RedPacketConfig[](0), "");

        // 测试无效的组件配置
        RedPacketConfig[] memory invalidConfigs = new RedPacketConfig[](1);
        BaseConfig memory invalidBase = baseConfig;
        invalidBase.distribute.distributor = address(0x1234); // 使用未注册的分发器
        invalidConfigs[0] = RedPacketConfig({
            base: invalidBase,
            assets: assets
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                IRedPacketFactory.InvalidComponent.selector,
                IRedPacketFactory.ComponentType.Distributor,
                address(0x1234)
            )
        );
        factory.createRedPacket{value: 1.005 ether}(invalidConfigs, "");

        // 测试无资产配置
        Asset[] memory emptyAssets = new Asset[](0);
        RedPacketConfig[] memory noAssetConfigs = new RedPacketConfig[](1);
        noAssetConfigs[0] = RedPacketConfig({
            base: baseConfig,
            assets: emptyAssets
        });
        vm.expectRevert(IRedPacketFactory.NoAssets.selector);
        factory.createRedPacket{value: 0}(noAssetConfigs, "");

        // 测试无份数
        BaseConfig memory zeroSharesBase = baseConfig;
        zeroSharesBase.shares = 0;
        RedPacketConfig[] memory zeroSharesConfigs = new RedPacketConfig[](1);
        zeroSharesConfigs[0] = RedPacketConfig({
            base: zeroSharesBase,
            assets: assets
        });
        vm.expectRevert(IRedPacketFactory.InvalidShares.selector);
        factory.createRedPacket{value: 1.005 ether}(zeroSharesConfigs, "");

        // 测试无访问控制
        BaseConfig memory noAccessBase = baseConfig;
        noAccessBase.access = new AccessConfig[](0);
        RedPacketConfig[] memory noAccessConfigs = new RedPacketConfig[](1);
        noAccessConfigs[0] = RedPacketConfig({
            base: noAccessBase,
            assets: assets
        });
        vm.expectRevert(IRedPacketFactory.NoAccessControl.selector);
        factory.createRedPacket{value: 1.005 ether}(noAccessConfigs, "");

        vm.stopPrank();
    }

    function test_registerComponents() public {
        address[] memory components = new address[](2);
        components[0] = makeAddr("component1");
        components[1] = makeAddr("component2");

        // 非 owner 不能注册
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.registerComponents(
            IRedPacketFactory.ComponentType.Access,
            components
        );

        // owner 可以注册
        vm.startPrank(factory.owner());

        // 不能注册零地址
        vm.expectRevert(IRedPacketFactory.ZeroAddress.selector);
        address[] memory invalidComponents = new address[](1);
        invalidComponents[0] = address(0);
        factory.registerComponents(
            IRedPacketFactory.ComponentType.Access,
            invalidComponents
        );

        // 正常注册
        factory.registerComponents(
            IRedPacketFactory.ComponentType.Access,
            components
        );
        bool[] memory results = factory.getRegisteredComponents(
            IRedPacketFactory.ComponentType.Access,
            components
        );
        assertTrue(results[0]);
        assertTrue(results[1]);

        vm.stopPrank();
    }

    function test_unregisterComponents() public {
        address[] memory components = new address[](2);
        components[0] = makeAddr("component1");
        components[1] = makeAddr("component2");

        // 先注册组件
        vm.startPrank(factory.owner());
        factory.registerComponents(
            IRedPacketFactory.ComponentType.Access,
            components
        );

        // 非 owner 不能注销
        vm.stopPrank();
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.unregisterComponents(
            IRedPacketFactory.ComponentType.Access,
            components
        );

        // owner 可以注销
        vm.prank(factory.owner());
        factory.unregisterComponents(
            IRedPacketFactory.ComponentType.Access,
            components
        );

        bool[] memory results = factory.getRegisteredComponents(
            IRedPacketFactory.ComponentType.Access,
            components
        );
        assertFalse(results[0]);
        assertFalse(results[1]);
    }

    function test_createRedPacket_Native() public {
        vm.startPrank(user);

        // 准备配置数据
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 1 ether,
            tokenId: 0
        });

        AccessConfig[] memory accessRules = new AccessConfig[](1);
        accessRules[0] = AccessConfig({
            validator: address(codeAccess),
            data: ""
        });

        TriggerConfig[] memory triggerRules = new TriggerConfig[](1);
        // triggerRules[0] = TriggerConfig({validator: address(0), data: ""});

        BaseConfig memory baseConfig = BaseConfig({
            name: "Test Red Packet",
            message: "Happy Testing!",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 100,
            access: accessRules,
            triggers: triggerRules,
            distribute: DistributeConfig({
                distributor: address(fixedDistributor),
                data: ""
            })
        });

        RedPacketConfig[] memory configs = new RedPacketConfig[](1);
        configs[0] = RedPacketConfig({base: baseConfig, assets: assets});

        // 设置ETH价格为2000U
        int256 ethPrice = 2000e8; // 8位小数
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, ethPrice, 0, 0, 0)
        );

        // 计算费用：100份 * 0.1U = 10U，10U / 2000U/ETH = 0.005 ETH
        (uint256 feeInETH, , ) = factory.calculateFee(100);
        assertEq(feeInETH, 0.005 ether);

        // 创建红包
        address redPacket = factory.createRedPacket{value: 1.005 ether}(
            configs,
            ""
        );

        // 验证红包创建
        assertTrue(redPacket != address(0), "Red packet not created");
        assertEq(factory.redPacketCreator(redPacket), user, "Wrong creator");
        assertTrue(factory.isCreator(user), "Not marked as creator");
        assertEq(
            factory.getRedPackets(user)[0],
            redPacket,
            "Red packet not recorded"
        );

        vm.stopPrank();
    }

    function test_createRedPacket_ERC20() public {
        vm.startPrank(user);

        // 准备 ERC20 资产
        uint256 amount = 100 ether;
        mockToken.approve(address(factory.PERMIT2()), type(uint256).max);

        // 设置ETH价格为2000U
        int256 ethPrice = 2000e8; // 8位小数
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, ethPrice, 0, 0, 0)
        );

        // 准备 permit2 数据
        ISignatureTransfer.TokenPermissions[]
            memory permitted = new ISignatureTransfer.TokenPermissions[](1);
        permitted[0] = ISignatureTransfer.TokenPermissions({
            token: address(mockToken),
            amount: amount
        });

        ISignatureTransfer.PermitBatchTransferFrom
            memory permitBatch = ISignatureTransfer.PermitBatchTransferFrom({
                permitted: permitted,
                nonce: block.timestamp,
                deadline: block.timestamp + 1 days
            });

        bytes memory signature;
        {
            // 生成签名
            bytes32 permitTypeHash = keccak256(
                "PermitBatchTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline)TokenPermissions(address token,uint256 amount)"
            );

            bytes32[] memory tokenPermissionsHashes = new bytes32[](1);
            tokenPermissionsHashes[0] = keccak256(
                abi.encode(
                    keccak256("TokenPermissions(address token,uint256 amount)"),
                    permitted[0].token,
                    permitted[0].amount
                )
            );

            bytes32 typedDataHash = keccak256(
                abi.encode(
                    permitTypeHash,
                    keccak256(abi.encodePacked(tokenPermissionsHashes)),
                    address(factory),
                    permitBatch.nonce,
                    permitBatch.deadline
                )
            );

            bytes32 digest = keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    keccak256(
                        abi.encode(
                            keccak256(
                                "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
                            ),
                            keccak256("Permit2"),
                            block.chainid,
                            address(factory.PERMIT2())
                        )
                    ),
                    typedDataHash
                )
            );

            (, uint256 pk) = makeAddrAndKey("user");
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
            signature = abi.encodePacked(r, s, v);
        }

        // 准备红包配置
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.ERC20,
            token: address(mockToken),
            amount: amount,
            tokenId: 0
        });

        AccessConfig[] memory accessRules = new AccessConfig[](1);
        accessRules[0] = AccessConfig({
            validator: address(codeAccess),
            data: "1"
        });

        TriggerConfig[] memory triggerRules = new TriggerConfig[](1);
        // triggerRules[0] = TriggerConfig({validator: address(0), data: ""});

        BaseConfig memory baseConfig = BaseConfig({
            name: "Test ERC20 Red Packet",
            message: "Happy Testing!",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 100,
            access: accessRules,
            triggers: triggerRules,
            distribute: DistributeConfig({
                distributor: address(fixedDistributor),
                data: ""
            })
        });

        RedPacketConfig[] memory configs = new RedPacketConfig[](1);
        configs[0] = RedPacketConfig({base: baseConfig, assets: assets});

        // 计算费用：100份 * 0.1U = 10U，10U / 2000U/ETH = 0.005 ETH
        (uint256 feeInETH, , ) = factory.calculateFee(100);
        assertEq(feeInETH, 0.005 ether);

        // 编码 permit 数据
        bytes memory permitData = abi.encode(permitBatch, signature);

        // 创建红包
        address redPacket = factory.createRedPacket{value: feeInETH}(
            configs,
            permitData
        );

        // 验证红包创建
        assertTrue(redPacket != address(0), "Red packet not created");
        assertEq(factory.redPacketCreator(redPacket), user, "Wrong creator");
        assertTrue(factory.isCreator(user), "Not marked as creator");
        assertEq(
            factory.getRedPackets(user)[0],
            redPacket,
            "Red packet not recorded"
        );

        vm.stopPrank();
    }

    function test_getters() public {
        // 创建一些测试数据
        vm.startPrank(user);

        // 设置ETH价格为2000U
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 1 ether,
            tokenId: 0
        });

        AccessConfig[] memory accessRules = new AccessConfig[](1);
        accessRules[0] = AccessConfig({
            validator: address(codeAccess),
            data: ""
        });

        BaseConfig memory baseConfig = BaseConfig({
            name: "Test Red Packet",
            message: "Happy Testing!",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 100,
            access: accessRules,
            triggers: new TriggerConfig[](0),
            distribute: DistributeConfig({
                distributor: address(fixedDistributor),
                data: ""
            })
        });

        RedPacketConfig[] memory configs = new RedPacketConfig[](1);
        configs[0] = RedPacketConfig({base: baseConfig, assets: assets});

        // 计算费用：100份 * 0.1U = 10U，10U / 2000U/ETH = 0.005 ETH
        (uint256 feeInETH, , ) = factory.calculateFee(100);

        // 创建两个红包
        address redPacket1 = factory.createRedPacket{value: 1 ether + feeInETH}(
            configs,
            ""
        );
        address redPacket2 = factory.createRedPacket{value: 1 ether + feeInETH}(
            configs,
            ""
        );
        vm.stopPrank();

        // 测试 getCreatorsCount
        assertEq(factory.getCreatorsCount(), 1);

        // 测试 getRedPackets
        address[] memory userRedPackets = factory.getRedPackets(user);
        assertEq(userRedPackets.length, 2);
        assertEq(userRedPackets[0], redPacket1);
        assertEq(userRedPackets[1], redPacket2);

        // 测试 getRedPacketCreator
        assertEq(factory.getRedPacketCreator(redPacket1), user);
        assertEq(factory.getRedPacketCreator(redPacket2), user);

        // 测试 getRegisteredComponents
        address[] memory componentsToCheck = new address[](2);
        componentsToCheck[0] = address(codeAccess);
        componentsToCheck[1] = makeAddr("nonRegisteredComponent");
        bool[] memory results = factory.getRegisteredComponents(
            IRedPacketFactory.ComponentType.Access,
            componentsToCheck
        );
        assertTrue(results[0]);
        assertFalse(results[1]);
    }

    function test_RedPacketCreatedEvent() public {
        vm.startPrank(user);

        // 设置ETH价格为2000U
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        // 准备红包配置
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 1 ether,
            tokenId: 0
        });

        AccessConfig[] memory accessRules = new AccessConfig[](1);
        accessRules[0] = AccessConfig({
            validator: address(codeAccess),
            data: ""
        });

        BaseConfig memory baseConfig = BaseConfig({
            name: "Test Red Packet",
            message: "Happy Testing!",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 100,
            access: accessRules,
            triggers: new TriggerConfig[](0),
            distribute: DistributeConfig({
                distributor: address(fixedDistributor),
                data: ""
            })
        });

        RedPacketConfig[] memory configs = new RedPacketConfig[](1);
        configs[0] = RedPacketConfig({base: baseConfig, assets: assets});

        // 计算费用
        (uint256 feeInETH, , ) = factory.calculateFee(100);

        // 期望事件被发出
        vm.expectEmit(false, true, false, false);
        // 我们不知道确切的红包地址，但我们知道创建者是user
        emit IRedPacketFactory.RedPacketCreated(address(0), user);

        vm.recordLogs();
        // 创建红包
        address redPacket = factory.createRedPacket{value: 1 ether + feeInETH}(
            configs,
            ""
        );

        // 验证事件日志
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // 找到RedPacketCreated事件
        bool found = false;
        for (uint i = 0; i < entries.length; i++) {
            // RedPacketCreated事件的topic[0]是事件签名
            if (
                entries[i].topics[0] ==
                keccak256("RedPacketCreated(address,address)")
            ) {
                // topic[1]是indexed redPacket地址
                // topic[2]是indexed creator地址
                assertEq(
                    address(uint160(uint256(entries[i].topics[1]))),
                    redPacket,
                    "Wrong red packet address in event"
                );
                assertEq(
                    address(uint160(uint256(entries[i].topics[2]))),
                    user,
                    "Wrong creator address in event"
                );
                found = true;
                break;
            }
        }
        assertTrue(found, "RedPacketCreated event not found");

        vm.stopPrank();
    }

    function test_createRedPacket_with_calldata() public {
        vm.startPrank(user);

        bytes
            memory data = hex"ef6f79970000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000002e0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000067a4dc12000000000000000000000000000000000000000000000000000000000001518000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000000000000000000000000000001310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000004311ea0a74a3f6ccb1467a829f686b9e6b66b7390000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003e0e90418692d4bcc70658a42c5b287e702796940000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002000000000000000000000000222d377f7ba38567492e4d253c69a0ec237366e60000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006046f37e5945c0000000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000194dbfbb67e0000000000000000000000000000000000000000000000000000000067a4ea260000000000000000000000000000000000000000000000000000000000000001000000000000000000000000222d377f7ba38567492e4d253c69a0ec237366e6000000000000000000000000000000000000000000000006046f37e5945c00000000000000000000000000000000000000000000000000000000000000000041844f6500d60dfecf1481ece0ae77d78377938560129dc524bdd8e16c84254a4a213920e2c1e862092d47fba7442c9f8d3e6b9f2f02dee09465efc060feedbb8c1b00000000000000000000000000000000000000000000000000000000000000";

        (bool success, bytes memory result) = address(
            0x9d789d724B25E7541B51d2Fec906e2D1F5C5f432
        ).call(data);
        require(success, "call failed");
        console.logBytes(result);
        vm.stopPrank();
    }

    receive() external payable {}
}
