// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Deploy} from "../script/deploy.s.sol";
import {PacketFactory} from "../src/PacketFactory.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {MockERC1155} from "../src/mocks/MockERC1155.sol";
import {IPacket} from "../src/interfaces/IPacket.sol";
import {IPacketFactory} from "../src/interfaces/IPacketFactory.sol";
import {ISignatureTransfer} from "@permit2/interfaces/ISignatureTransfer.sol";
import {Asset, AssetType, BaseConfig, PacketConfig} from "../src/interfaces/types.sol";
import {AccessConfig} from "../src/interfaces/IAccess.sol";
import {TriggerConfig} from "../src/interfaces/ITrigger.sol";
import {DistributeConfig} from "../src/interfaces/IDistributor.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {Ownable} from "@oz/contracts/access/Ownable.sol";

contract PacketFactoryTest is Deploy, Test {
    address user;
    address user2;
    MockERC20 mockToken;
    MockERC721 mockNFT;
    MockERC1155 mockERC1155;

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

        // 部署测试NFT
        mockNFT = new MockERC721("Test NFT", "TNFT");
        mockNFT.mint(user, 1);
        mockNFT.mint(user, 2);
        mockNFT.mint(user2, 3);

        // 部署测试ERC1155
        mockERC1155 = new MockERC1155();
        mockERC1155.mint(user, 1, 100, "");
        mockERC1155.mint(user, 2, 50, "");
        mockERC1155.mint(user2, 3, 75, "");

        // invariant test
        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PacketFactory.setFeeReceiver.selector;
        selectors[1] = PacketFactory.setFeeShareDenominator.selector;
        selectors[2] = PacketFactory.registerComponents.selector;
        selectors[3] = PacketFactory.unregisterComponents.selector;
        selectors[4] = PacketFactory.createPacket.selector;
        targetSelector(
            FuzzSelector({addr: address(factory), selectors: selectors})
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
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
        vm.expectRevert(IPacketFactory.InvalidFeeReceiver.selector);
        factory.setFeeReceiver(address(0));

        // 不能设置零分母
        vm.prank(factory.owner());
        vm.expectRevert(IPacketFactory.InvalidFeeConfig.selector);
        factory.setFeeShareDenominator(0);
    }

    function test_calculateFee() public {
        // 测试负价格情况
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, -1, 0, 0, 0)
        );
        vm.expectRevert(IPacketFactory.InvalidPrice.selector);
        factory.calculateFee(100);
    }

    function _createBaseConfig() internal view returns (BaseConfig memory) {
        AccessConfig[] memory accessRules = new AccessConfig[](1);
        accessRules[0] = AccessConfig({
            validator: address(codeAccess),
            data: ""
        });

        return
            BaseConfig({
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
    }

    function test_createPacket_errors() public {
        vm.startPrank(user);

        PacketConfig[] memory configs = new PacketConfig[](1);
        BaseConfig memory baseConfig = _createBaseConfig();
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 1 ether,
            tokenId: 0
        });
        configs[0] = PacketConfig({base: baseConfig, assets: assets});

        // 设置ETH价格
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        // 测试ETH金额不足
        vm.expectRevert(
            abi.encodeWithSelector(
                IPacketFactory.InvalidEthAmount.selector,
                1.005 ether
            )
        );
        factory.createPacket{value: 1 ether}(configs, "");

        // 测试空配置数组
        vm.expectRevert(IPacketFactory.EmptyConfigs.selector);
        factory.createPacket{value: 1 ether}(new PacketConfig[](0), "");

        // 测试无效的组件配置
        PacketConfig[] memory invalidConfigs = new PacketConfig[](1);
        BaseConfig memory invalidBase = _createBaseConfig();
        invalidBase.distribute.distributor = address(0x1234); // 使用未注册的分发器
        invalidConfigs[0] = PacketConfig({base: invalidBase, assets: assets});

        vm.expectRevert(
            abi.encodeWithSelector(
                IPacketFactory.InvalidComponent.selector,
                IPacketFactory.ComponentType.Distributor,
                address(0x1234)
            )
        );
        factory.createPacket{value: 1.005 ether}(invalidConfigs, "");

        // 测试无资产配置
        Asset[] memory emptyAssets = new Asset[](0);
        PacketConfig[] memory noAssetConfigs = new PacketConfig[](1);
        noAssetConfigs[0] = PacketConfig({
            base: _createBaseConfig(),
            assets: emptyAssets
        });
        vm.expectRevert(IPacketFactory.NoAssets.selector);
        factory.createPacket{value: 0}(noAssetConfigs, "");

        // 测试无份数
        BaseConfig memory zeroSharesBase = _createBaseConfig();
        zeroSharesBase.shares = 0;
        PacketConfig[] memory zeroSharesConfigs = new PacketConfig[](1);
        zeroSharesConfigs[0] = PacketConfig({
            base: zeroSharesBase,
            assets: assets
        });
        vm.expectRevert(IPacketFactory.InvalidShares.selector);
        factory.createPacket{value: 1.005 ether}(zeroSharesConfigs, "");

        // 测试无访问控制
        BaseConfig memory noAccessBase = _createBaseConfig();
        noAccessBase.access = new AccessConfig[](0);
        noAccessBase.shares = 100;
        PacketConfig[] memory noAccessConfigs = new PacketConfig[](1);
        noAccessConfigs[0] = PacketConfig({base: noAccessBase, assets: assets});
        vm.expectRevert(IPacketFactory.NoAccessControl.selector);
        factory.createPacket{value: 1.005 ether}(noAccessConfigs, "");

        // 测试InvalidTokenAmount
        Asset[] memory invalidTokenAmountAssets = new Asset[](1);
        invalidTokenAmountAssets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 0,
            tokenId: 0
        });
        PacketConfig[] memory invalidTokenAmountConfigs = new PacketConfig[](1);
        invalidTokenAmountConfigs[0] = PacketConfig({
            base: _createBaseConfig(),
            assets: invalidTokenAmountAssets
        });
        vm.expectRevert(
            abi.encodeWithSelector(
                IPacketFactory.InvalidTokenAmount.selector,
                address(0)
            )
        );
        factory.createPacket{value: 1.005 ether}(invalidTokenAmountConfigs, "");

        vm.stopPrank();
    }

    function test_registerComponents() public {
        address[] memory components = new address[](2);
        components[0] = makeAddr("component1");
        components[1] = makeAddr("component2");

        // 非 owner 不能注册
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        factory.registerComponents(
            IPacketFactory.ComponentType.Access,
            components
        );

        // owner 可以注册
        vm.startPrank(factory.owner());

        // 不能注册零地址
        vm.expectRevert(IPacketFactory.ZeroAddress.selector);
        address[] memory invalidComponents = new address[](1);
        invalidComponents[0] = address(0);
        factory.registerComponents(
            IPacketFactory.ComponentType.Access,
            invalidComponents
        );

        // 正常注册
        factory.registerComponents(
            IPacketFactory.ComponentType.Access,
            components
        );
        bool[] memory results = factory.getRegisteredComponents(
            IPacketFactory.ComponentType.Access,
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
            IPacketFactory.ComponentType.Access,
            components
        );

        // 非 owner 不能注销
        vm.stopPrank();
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        factory.unregisterComponents(
            IPacketFactory.ComponentType.Access,
            components
        );

        // owner 可以注销
        vm.prank(factory.owner());
        factory.unregisterComponents(
            IPacketFactory.ComponentType.Access,
            components
        );

        bool[] memory results = factory.getRegisteredComponents(
            IPacketFactory.ComponentType.Access,
            components
        );
        assertFalse(results[0]);
        assertFalse(results[1]);
    }

    function test_createPacket_Native() public {
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

        PacketConfig[] memory configs = new PacketConfig[](1);
        configs[0] = PacketConfig({base: baseConfig, assets: assets});

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
        address packet = factory.createPacket{value: 1.005 ether}(configs, "");

        // 验证红包创建
        assertTrue(packet != address(0), "Red packet not created");
        assertEq(IPacket(packet).creator(), user, "Wrong creator");
        assertEq(factory.creatorsCount(), 1, "Creator count not incremented");
        assertEq(
            factory.getPackets(user)[0],
            packet,
            "Red packet not recorded"
        );

        vm.stopPrank();
    }

    function test_createPacket_ERC20() public {
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

        PacketConfig[] memory configs = new PacketConfig[](1);
        configs[0] = PacketConfig({base: baseConfig, assets: assets});

        // 计算费用：100份 * 0.1U = 10U，10U / 2000U/ETH = 0.005 ETH
        (uint256 feeInETH, , ) = factory.calculateFee(100);
        assertEq(feeInETH, 0.005 ether);

        // 编码 permit 数据
        bytes memory permitData = abi.encode(permitBatch, signature);

        // 创建红包
        address packet = factory.createPacket{value: feeInETH}(
            configs,
            permitData
        );

        // 验证红包创建
        assertTrue(packet != address(0), "Red packet not created");
        assertEq(IPacket(packet).creator(), user, "Wrong creator");
        assertEq(factory.creatorsCount(), 1, "Creator count not incremented");
        assertEq(
            factory.getPackets(user)[0],
            packet,
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

        PacketConfig[] memory configs = new PacketConfig[](1);
        configs[0] = PacketConfig({base: baseConfig, assets: assets});

        // 计算费用：100份 * 0.1U = 10U，10U / 2000U/ETH = 0.005 ETH
        (uint256 feeInETH, , ) = factory.calculateFee(100);

        // 创建两个红包
        address packet1 = factory.createPacket{value: 1 ether + feeInETH}(
            configs,
            ""
        );
        address packet2 = factory.createPacket{value: 1 ether + feeInETH}(
            configs,
            ""
        );
        vm.stopPrank();

        // 测试 getCreatorsCount
        assertEq(factory.creatorsCount(), 1);

        // 测试 getPackets
        address[] memory userPackets = factory.getPackets(user);
        assertEq(userPackets.length, 2);
        assertEq(userPackets[0], packet1);
        assertEq(userPackets[1], packet2);

        // 测试 getRegisteredComponents
        address[] memory componentsToCheck = new address[](2);
        componentsToCheck[0] = address(codeAccess);
        componentsToCheck[1] = makeAddr("nonRegisteredComponent");
        bool[] memory results = factory.getRegisteredComponents(
            IPacketFactory.ComponentType.Access,
            componentsToCheck
        );
        assertTrue(results[0]);
        assertFalse(results[1]);
    }

    function test_PacketCreatedEvent() public {
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

        PacketConfig[] memory configs = new PacketConfig[](1);
        configs[0] = PacketConfig({base: baseConfig, assets: assets});

        // 计算费用
        (uint256 feeInETH, , ) = factory.calculateFee(100);

        // 期望事件被发出
        vm.expectEmit(false, true, false, false);
        // 我们不知道确切的红包地址，但我们知道创建者是user
        emit IPacketFactory.PacketCreated(address(0), user);

        vm.recordLogs();
        // 创建红包
        address packet = factory.createPacket{value: 1 ether + feeInETH}(
            configs,
            ""
        );

        // 验证事件日志
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // 找到PacketCreated事件
        bool found = false;
        for (uint i = 0; i < entries.length; i++) {
            // PacketCreated事件的topic[0]是事件签名
            if (
                entries[i].topics[0] ==
                keccak256("PacketCreated(address,address)")
            ) {
                // topic[1]是indexed packet地址
                // topic[2]是indexed creator地址
                assertEq(
                    address(uint160(uint256(entries[i].topics[1]))),
                    packet,
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
        assertTrue(found, "PacketCreated event not found");

        vm.stopPrank();
    }

    function test_createPacket_with_calldata() public {
        vm.startPrank(user);

        bytes memory data = hex"";

        (bool success, bytes memory result) = address(
            0x9d789d724B25E7541B51d2Fec906e2D1F5C5f432
        ).call(data);
        require(success, "call failed");
        console.logBytes(result);
        vm.stopPrank();
    }

    // 测试创建多个红包
    function test_createMultiplePackets() public {
        vm.startPrank(user);

        // 设置ETH价格为2000U
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        // 准备基础配置
        BaseConfig memory baseConfig = _createBaseConfig();
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 1 ether,
            tokenId: 0
        });

        // 创建多个红包配置
        PacketConfig[] memory configs = new PacketConfig[](3);
        for (uint i = 0; i < 3; i++) {
            configs[i] = PacketConfig({base: baseConfig, assets: assets});
        }

        // 计算总费用：300份 * 0.1U = 30U，30U / 2000U/ETH = 0.015 ETH
        (uint256 feeInETH, , ) = factory.calculateFee(300);
        assertEq(feeInETH, 0.015 ether);

        // 创建红包
        address packet = factory.createPacket{value: 3 ether + feeInETH}(
            configs,
            ""
        );

        // 验证红包创建
        assertTrue(packet != address(0), "Red packet not created");
        assertEq(IPacket(packet).creator(), user, "Wrong creator");
        assertEq(factory.creatorsCount(), 1, "Creator count not incremented");

        vm.stopPrank();
    }

    // 测试创建包含多种资产的红包
    function test_createPacket_MultiAssets() public {
        vm.startPrank(user);

        // 设置ETH价格
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        // 准备多种资产
        Asset[] memory assets = new Asset[](4);
        assets[0] = Asset({
            assetType: AssetType.Native,
            token: address(0),
            amount: 1 ether,
            tokenId: 0
        });
        assets[1] = Asset({
            assetType: AssetType.ERC20,
            token: address(mockToken),
            amount: 100 ether,
            tokenId: 0
        });
        assets[2] = Asset({
            assetType: AssetType.ERC721,
            token: address(mockNFT),
            amount: 1,
            tokenId: 1
        });
        assets[3] = Asset({
            assetType: AssetType.ERC1155,
            token: address(mockERC1155),
            amount: 50,
            tokenId: 1
        });

        // 准备红包配置
        PacketConfig[] memory configs = new PacketConfig[](1);
        configs[0] = PacketConfig({base: _createBaseConfig(), assets: assets});

        // 准备 permit2 数据
        ISignatureTransfer.TokenPermissions[]
            memory permitted = new ISignatureTransfer.TokenPermissions[](1);
        permitted[0] = ISignatureTransfer.TokenPermissions({
            token: address(mockToken),
            amount: 100 ether
        });

        ISignatureTransfer.PermitBatchTransferFrom
            memory permitBatch = ISignatureTransfer.PermitBatchTransferFrom({
                permitted: permitted,
                nonce: block.timestamp,
                deadline: block.timestamp + 1 days
            });

        bytes memory signature;
        {
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

        // 编码 permit 数据
        bytes memory permitData = abi.encode(permitBatch, signature);

        // 计算费用：100份 * 0.1U = 10U，10U / 2000U/ETH = 0.005 ETH
        (uint256 feeInETH, , ) = factory.calculateFee(100);

        // 授权代币
        mockToken.approve(address(factory.PERMIT2()), type(uint256).max);
        mockNFT.setApprovalForAll(address(factory), true);
        mockERC1155.setApprovalForAll(address(factory), true);

        // 创建红包
        address packet = factory.createPacket{value: 1 ether + feeInETH}(
            configs,
            permitData
        );

        // 验证红包创建
        assertTrue(packet != address(0), "Red packet not created");
        assertEq(IPacket(packet).creator(), user, "Wrong creator");

        // 验证资产转移
        assertEq(mockNFT.ownerOf(1), packet, "NFT not transferred");
        assertEq(
            mockERC1155.balanceOf(packet, 1),
            50,
            "ERC1155 not transferred"
        );
        assertEq(
            mockToken.balanceOf(packet),
            100 ether,
            "ERC20 not transferred"
        );
        assertEq(packet.balance, 1 ether, "ETH not transferred");

        vm.stopPrank();
    }

    // Fuzz test: 测试不同份数的费用计算
    function testFuzz_calculateFee(
        uint256 shares,
        uint256 feeShareDenominator
    ) public {
        // 限制份数范围，避免溢出
        shares = bound(shares, 1, 1000000);
        feeShareDenominator = bound(feeShareDenominator, 1, 1000000);

        vm.prank(factory.owner());
        factory.setFeeShareDenominator(feeShareDenominator);

        // 设置ETH价格为2000U
        vm.mockCall(
            address(factory.ETH_USD_FEED()),
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        (uint256 feeInETH, uint256 feeInUSD, ) = factory.calculateFee(shares);

        // 验证USD费用计算
        assertEq(feeInUSD, shares * (1e6 / factory.feeShareDenominator()));

        // 验证ETH费用计算
        uint256 expectedFeeInETH = (feeInUSD * 1e18) / (2000e6);
        assertEq(feeInETH, expectedFeeInETH);
    }

    receive() external payable {}
}
