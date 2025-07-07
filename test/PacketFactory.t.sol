// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PacketFactory} from "../src/PacketFactory.sol";
import {Packet} from "../src/Packet.sol";
import {UpgradeableBeacon} from "@oz/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IPacketFactory} from "../src/interfaces/IPacketFactory.sol";
import {Asset, AssetType, BaseConfig, AccessType, DistributeType, PacketConfig} from "../src/interfaces/types.sol";
import {Permit2 as MockPermit2} from "../src/mocks/MockPermit2/Permit2.sol";
import {Ownable} from "@oz/contracts/access/Ownable.sol";

contract PacketFactoryTest is Test {
    PacketFactory factory;
    UpgradeableBeacon beacon;
    Packet implementation;
    MockPermit2 mockPermit2;
    address feeReceiver;
    address owner;
    address user;
    MockERC20 mockToken;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        vm.deal(user, 100 ether);

        feeReceiver = makeAddr("feeReceiver");
        vm.prank(owner);

        // 部署核心合约
        implementation = new Packet();
        beacon = new UpgradeableBeacon(address(implementation), owner);
        mockPermit2 = new MockPermit2();

        factory = new PacketFactory(
            owner,
            address(beacon),
            address(mockPermit2),
            feeReceiver
        );

        // 部署测试代币
        mockToken = new MockERC20("Test Token", "TEST");
        mockToken.mint(user, 1000 ether);
    }

    function _createPacketConfig(
        AssetType assetType,
        address token,
        uint256 amount
    ) internal view returns (PacketConfig memory) {
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({assetType: assetType, token: token, amount: amount});

        BaseConfig memory baseConfig = BaseConfig({
            name: "Test Packet",
            message: "For testing",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 10,
            accessType: AccessType.Public,
            merkleRoot: bytes32(0),
            distributeType: DistributeType.Average
        });

        return PacketConfig({base: baseConfig, assets: assets});
    }

    function test_calculateFee() public {
        assertEq(factory.calculateFee(1), 0.001 ether, "Fee for 1 share");
        assertEq(factory.calculateFee(100), 0.001 ether, "Fee for 100 shares");
        assertEq(factory.calculateFee(101), 0.01 ether, "Fee for 101 shares");
        assertEq(factory.calculateFee(1000), 0.01 ether, "Fee for 1000 shares");
        assertEq(factory.calculateFee(1001), 0.05 ether, "Fee for 1001 shares");
        assertEq(factory.calculateFee(5000), 0.05 ether, "Fee for 5000 shares");
    }

    function test_createPacket_Native() public {
        vm.startPrank(user);

        // 1. 准备配置
        uint256 ethAmount = 1 ether;
        PacketConfig memory config = _createPacketConfig(
            AssetType.Native,
            address(0),
            ethAmount
        );

        // 2. 计算费用
        uint256 fee = factory.calculateFee(config.base.shares);
        assertEq(fee, 0.001 ether);

        // 3. 期望事件
        vm.expectEmit(false, true, false, true);
        emit IPacketFactory.PacketCreated(address(0), user); // 地址未知，所以用0

        // 4. 创建红包
        address packet = factory.createPacket{value: ethAmount + fee}(
            config,
            ""
        );

        // 5. 验证
        assertTrue(packet != address(0), "Packet address is zero");
        assertEq(packet.balance, ethAmount, "ETH not transferred to packet");

        Packet newPacket = Packet(payable(packet));
        assertEq(newPacket.creator(), user, "Creator mismatch");

        BaseConfig memory retrievedBase = newPacket.config();
        assertEq(retrievedBase.shares, config.base.shares, "Shares mismatch");

        vm.stopPrank();
    }

    function test_createPacket_errors() public {
        vm.startPrank(user);

        // 1. 测试单一资产限制 (assets.length != 1)
        PacketConfig memory multiAssetConfig = _createPacketConfig(
            AssetType.Native,
            address(0),
            1 ether
        );
        // 手动创建一个多资产数组
        Asset[] memory multiAssets = new Asset[](2);
        multiAssets[0] = multiAssetConfig.assets[0];
        multiAssets[1] = Asset({
            assetType: AssetType.ERC20,
            token: address(mockToken),
            amount: 100 ether
        });
        multiAssetConfig.assets = multiAssets;

        vm.expectRevert("MVP: Only one asset type per packet");
        factory.createPacket(multiAssetConfig, "");

        // 2. 测试白名单模式下 merkleRoot 为空
        PacketConfig memory noMerkleRootConfig = _createPacketConfig(
            AssetType.Native,
            address(0),
            1 ether
        );
        noMerkleRootConfig.base.accessType = AccessType.Whitelist;
        // merkleRoot 默认为 bytes32(0)
        vm.expectRevert(IPacketFactory.NoAccessControl.selector);
        factory.createPacket(noMerkleRootConfig, "");

        // 3. 测试 ETH 不足
        PacketConfig memory ethConfig = _createPacketConfig(
            AssetType.Native,
            address(0),
            1 ether
        );
        uint256 fee = factory.calculateFee(ethConfig.base.shares);
        uint256 requiredValue = 1 ether + fee;

        vm.expectRevert(
            abi.encodeWithSelector(
                IPacketFactory.InvalidEthAmount.selector,
                requiredValue
            )
        );
        factory.createPacket{value: requiredValue - 1}(ethConfig, "");

        vm.stopPrank();
    }
}
