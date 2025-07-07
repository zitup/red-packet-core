// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Packet} from "../src/Packet.sol";
import {IPacket} from "../src/interfaces/IPacket.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {Asset, AssetType, BaseConfig, PacketConfig, AccessType, DistributeType} from "../src/interfaces/types.sol";

contract PacketTest is Test {
    address creator;
    address factory;
    address claimer;
    MockERC20 mockToken;
    Packet packet;

    function setUp() public {
        // 设置测试账户
        creator = makeAddr("creator");
        factory = makeAddr("factory");
        claimer = makeAddr("claimer");
        vm.deal(creator, 100 ether);
        vm.deal(claimer, 100 ether);

        // 部署测试代币
        mockToken = new MockERC20("Test Token", "TEST");
        mockToken.mint(creator, 1000 ether);

        // 部署红包合约
        packet = new Packet();
    }

    function test_claim_public_average_erc20() public {
        // 1. 准备配置和初始化
        uint256 totalAmount = 100 ether;
        uint256 shares = 10;

        PacketConfig memory config;
        config.base = BaseConfig({
            name: "Test",
            message: "",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: shares,
            accessType: AccessType.Public,
            merkleRoot: bytes32(0),
            distributeType: DistributeType.Average
        });
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.ERC20,
            token: address(mockToken),
            amount: totalAmount
        });
        config.assets = assets;

        vm.startPrank(factory);
        packet.initialize(config, creator);
        vm.stopPrank();

        // 2. 准备资产
        vm.startPrank(creator);
        mockToken.transfer(address(packet), totalAmount);
        vm.stopPrank();

        // 3. 领取
        vm.startPrank(claimer);
        bool success = packet.claim(new bytes32[](0)); // 公开模式，proof为空
        assertTrue(success, "Claim failed");
        vm.stopPrank();

        // 4. 验证
        uint256 expectedAmount = totalAmount / shares;
        assertEq(
            mockToken.balanceOf(claimer),
            expectedAmount,
            "Claimer did not receive correct amount"
        );

        assertTrue(packet.claimed(claimer), "Claimer status not updated");
        assertEq(packet.claimedShares(), 1, "Claimed shares not incremented");
    }

    function test_claim_revert_AlreadyClaimed() public {
        // 1. 准备配置和初始化
        uint256 totalAmount = 100 ether;
        PacketConfig memory config;
        config.base = BaseConfig({
            name: "Test",
            message: "",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 10,
            accessType: AccessType.Public,
            merkleRoot: bytes32(0),
            distributeType: DistributeType.Average
        });
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.ERC20,
            token: address(mockToken),
            amount: totalAmount
        });
        config.assets = assets;

        vm.startPrank(factory);
        packet.initialize(config, creator);
        vm.stopPrank();

        // 2. 准备资产
        vm.startPrank(creator);
        mockToken.transfer(address(packet), totalAmount);
        vm.stopPrank();

        // 3. 第一次领取
        vm.startPrank(claimer);
        packet.claim(new bytes32[](0));

        // 4. 第二次领取，应该失败
        vm.expectRevert(IPacket.AlreadyClaimed.selector);
        packet.claim(new bytes32[](0));
        vm.stopPrank();
    }

    function test_claim_whitelist() public {
        // 1. 准备 Merkle 树
        bytes32[] memory leaves = new bytes32[](2);
        leaves[0] = keccak256(abi.encodePacked(claimer));
        leaves[1] = keccak256(abi.encodePacked(makeAddr("another_user")));

        // 手动计算 Root: H(H(leaf1), H(leaf2)) -> 在这个简单例子中 H(leaf) = leaf
        bytes32 root = keccak256(abi.encodePacked(leaves[0], leaves[1]));

        // 2. 准备配置和初始化
        PacketConfig memory config;
        config.base = BaseConfig({
            name: "Whitelist Test",
            message: "",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: 2,
            accessType: AccessType.Whitelist,
            merkleRoot: root,
            distributeType: DistributeType.Average
        });
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.ERC20,
            token: address(mockToken),
            amount: 100 ether
        });
        config.assets = assets;

        vm.startPrank(factory);
        packet.initialize(config, creator);
        vm.stopPrank();

        // 3. 准备资产和 Proof
        vm.startPrank(creator);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = leaves[1]; // claimer 的 proof 是另一个 leaf

        // 4. 使用有效的 proof 领取
        vm.startPrank(claimer);
        assertTrue(packet.claim(proof));
        vm.stopPrank();

        // 5. 验证领取成功
        assertEq(mockToken.balanceOf(claimer), 50 ether);
        assertTrue(packet.claimed(claimer));

        // 6. 使用无效的 proof 领取 (AccessDenied)
        address nonWhitelisted = makeAddr("non_whitelisted");
        vm.startPrank(nonWhitelisted);
        vm.expectRevert(IPacket.AccessDenied.selector);
        packet.claim(proof); // 用别人的 proof
        vm.stopPrank();
    }

    function test_claim_lucky() public {
        // 1. 准备配置和初始化
        uint256 totalAmount = 100 ether;
        uint256 shares = 10;

        PacketConfig memory config;
        config.base = BaseConfig({
            name: "Lucky Test",
            message: "",
            startTime: block.timestamp,
            durationTime: 1 days,
            shares: shares,
            accessType: AccessType.Public,
            merkleRoot: bytes32(0),
            distributeType: DistributeType.Lucky
        });
        Asset[] memory assets = new Asset[](1);
        assets[0] = Asset({
            assetType: AssetType.ERC20,
            token: address(mockToken),
            amount: totalAmount
        });
        config.assets = assets;

        vm.startPrank(factory);
        packet.initialize(config, creator);
        vm.stopPrank();

        // 2. 准备资产
        vm.startPrank(creator);
        mockToken.transfer(address(packet), totalAmount);
        vm.stopPrank();

        // 3. 领取
        vm.startPrank(claimer);
        uint256 balanceBefore = mockToken.balanceOf(claimer);
        assertTrue(packet.claim(new bytes32[](0)));
        uint256 balanceAfter = mockToken.balanceOf(claimer);
        vm.stopPrank();

        // 4. 验证
        uint256 receivedAmount = balanceAfter - balanceBefore;
        assertTrue(receivedAmount > 0, "Received amount should be > 0");
        assertTrue(receivedAmount <= totalAmount, "Received amount too high");

        assertTrue(packet.claimed(claimer));
        assertEq(packet.claimedShares(), 1);
    }
}
