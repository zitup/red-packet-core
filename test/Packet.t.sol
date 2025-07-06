// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Deploy} from "../script/deploy.s.sol";
import {Test} from "forge-std/Test.sol";
import {Strings} from "@oz/contracts/utils/Strings.sol";
import {Packet} from "../src/Packet.sol";
import {IPacket} from "../src/interfaces/IPacket.sol";
import {IAggregatorV3} from "../src/interfaces/IAggregatorV3.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockERC721} from "../src/mocks/MockERC721.sol";
import {MockERC1155} from "../src/mocks/MockERC1155.sol";
import {Asset, AssetType, BaseConfig, PacketConfig, AccessConfig, TriggerConfig, DistributeConfig} from "../src/interfaces/types.sol";

contract PacketTest is Deploy, Test {
    using Strings for uint256;

    address user;
    address user2;
    Packet packet;
    MockERC20 mockToken;
    MockERC721 mockNFT;
    MockERC1155 mockERC1155;
    // import { buildPoseidon } from "../src/poseidon_wasm.js";
    // const poseidon = await buildPoseidon();
    // poseidon([utils.keccak256(utils.toUtf8Bytes('test'))]);
    bytes codeHash =
        abi.encode(
            14119624679937866494060478726858195062746196614862478686817116320419327437678
        );

    function setUp() public {
        // 设置测试账户
        user = makeAddr("user");
        user2 = makeAddr("user2");
        vm.deal(user, 100 ether);
        vm.deal(user2, 100 ether);

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

        // 部署红包合约
        packet = new Packet();
    }

    function test_initialize() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 验证初始化结果
        assertEq(packet.factory(), address(factory));
        assertEq(packet.creator(), user);
        assertEq(packet.createTime(), block.timestamp);
    }

    function test_initialize_revert_NotFactory() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.expectRevert(IPacket.NotFactory.selector);
        packet.initialize(configs, user);
    }

    function test_claim_single() public {
        // 准备红包配置
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        mockNFT.transferFrom(user, address(packet), 1);
        mockERC1155.safeTransferFrom(user, address(packet), 1, 50, "");
        vm.deal(address(packet), 1 ether);
        vm.stopPrank();

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 领取红包
        vm.startPrank(user2);
        bool success = packet.claim(0, proofs);
        assertTrue(success);

        // 验证领取结果
        assertTrue(packet.claimed(0, user2));
        assertEq(packet.claimedShares(0), 1);
        assertEq(mockToken.balanceOf(user2), 1100 ether); // 原有1000 + 领取100
        assertEq(mockNFT.ownerOf(1), user2);
        assertEq(mockERC1155.balanceOf(user2, 1), 50);
        assertEq(user2.balance, 101 ether); // 原有100 + 领取1

        vm.stopPrank();
    }

    function test_claim_all() public {
        // 准备多个红包配置
        PacketConfig[] memory configs = new PacketConfig[](2);
        configs[0] = _createPacketConfigs()[0];
        configs[1] = _createPacketConfigs()[0];

        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 200 ether); // 两个红包各100
        mockNFT.transferFrom(user, address(packet), 1);
        mockNFT.transferFrom(user, address(packet), 2);
        mockERC1155.safeTransferFrom(user, address(packet), 1, 100, "");
        vm.deal(address(packet), 2 ether); // 两个红包各1
        vm.stopPrank();

        // 准备访问证明
        bytes[][] memory proofs = new bytes[][](2);
        proofs[0] = new bytes[](1);
        proofs[0][0] = codeHash;
        proofs[1] = new bytes[](1);
        proofs[1][0] = codeHash;

        // 领取所有红包
        vm.startPrank(user2);
        packet.claimAll(proofs);

        // 验证领取结果
        assertTrue(packet.claimed(0, user2));
        assertTrue(packet.claimed(1, user2));
        assertEq(packet.claimedShares(0), 1);
        assertEq(packet.claimedShares(1), 1);
        assertEq(mockToken.balanceOf(user2), 1200 ether); // 原有1000 + 领取200
        assertEq(mockNFT.ownerOf(1), user2);
        assertEq(mockNFT.ownerOf(2), user2);
        assertEq(mockERC1155.balanceOf(user2, 1), 100);
        assertEq(user2.balance, 102 ether); // 原有100 + 领取2

        vm.stopPrank();
    }

    function test_claim_revert_AlreadyClaimed() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 第一次领取
        vm.startPrank(user2);
        packet.claim(0, proofs);

        // 第二次领取应该失败
        vm.expectRevert(IPacket.AlreadyClaimed.selector);
        packet.claim(0, proofs);
        vm.stopPrank();
    }

    function test_claim_revert_NoRemainingShares() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 用户2领取
        vm.startPrank(user2);
        packet.claim(0, proofs);
        vm.stopPrank();

        // 创建用户3并尝试领取
        address user3 = makeAddr("user3");
        vm.startPrank(user3);
        vm.expectRevert(IPacket.NoRemainingShares.selector);
        packet.claim(0, proofs);
        vm.stopPrank();
    }

    function test_claim_revert_NotStarted() public {
        // 创建一个未来开始的红包
        PacketConfig[] memory configs = _createPacketConfigs();
        configs[0].base.startTime = block.timestamp + 1 days;

        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 尝试领取应该失败
        vm.startPrank(user2);
        vm.expectRevert("RP: Not started");
        packet.claim(0, proofs);
        vm.stopPrank();
    }

    function test_claim_revert_Expired() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 时间快进超过有效期
        vm.warp(block.timestamp + 8 days);

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 尝试领取应该失败
        vm.startPrank(user2);
        vm.expectRevert("RP: Expired");
        packet.claim(0, proofs);
        vm.stopPrank();
    }

    function test_withdrawAllAssets() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        mockNFT.transferFrom(user, address(packet), 1);
        mockERC1155.safeTransferFrom(user, address(packet), 1, 50, "");
        vm.deal(address(packet), 1 ether);
        vm.stopPrank();

        // 等待红包过期
        vm.warp(block.timestamp + 8 days);

        // 准备提取参数
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockToken);

        IPacket.NFTInfo[] memory nfts = new IPacket.NFTInfo[](1);
        nfts[0] = IPacket.NFTInfo({token: address(mockNFT), tokenId: 1});

        IPacket.ERC1155Info[] memory erc1155s = new IPacket.ERC1155Info[](1);
        erc1155s[0] = IPacket.ERC1155Info({
            token: address(mockERC1155),
            tokenId: 1
        });

        // 提取资产
        vm.startPrank(user);
        packet.withdrawAllAssets(tokens, nfts, erc1155s, address(0));

        // 验证提取结果
        assertEq(mockToken.balanceOf(user), 1000 ether);
        assertEq(mockNFT.ownerOf(1), user);
        assertEq(mockERC1155.balanceOf(user, 1), 100);
        assertEq(user.balance, 101 ether);

        vm.stopPrank();
    }

    function test_withdrawAllAssets_revert_NotExpired() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备提取参数
        address[] memory tokens = new address[](0);
        IPacket.NFTInfo[] memory nfts = new IPacket.NFTInfo[](0);
        IPacket.ERC1155Info[] memory erc1155s = new IPacket.ERC1155Info[](0);

        // 尝试提取应该失败
        vm.startPrank(user);
        vm.expectRevert(IPacket.NotExpired.selector);
        packet.withdrawAllAssets(tokens, nfts, erc1155s, address(0));
        vm.stopPrank();
    }

    function test_withdrawAllAssets_revert_NotCreator() public {
        PacketConfig[] memory configs = _createPacketConfigs();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 等待红包过期
        vm.warp(block.timestamp + 8 days);

        // 准备提取参数
        address[] memory tokens = new address[](0);
        IPacket.NFTInfo[] memory nfts = new IPacket.NFTInfo[](0);
        IPacket.ERC1155Info[] memory erc1155s = new IPacket.ERC1155Info[](0);

        // 非创建者尝试提取应该失败
        vm.startPrank(user2);
        vm.expectRevert(IPacket.NotCreator.selector);
        packet.withdrawAllAssets(tokens, nfts, erc1155s, address(0));
        vm.stopPrank();
    }

    // 测试价格触发条件
    function test_claim_with_price_trigger() public {
        PacketConfig[] memory configs = _createPacketConfigsWithPriceTrigger();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        // 设置ETH价格为2000U
        vm.mockCall(
            ETH_USD_FEED[block.chainid],
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0)
        );

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 领取红包
        vm.startPrank(user2);
        bool success = packet.claim(0, proofs);
        assertTrue(success);
        vm.stopPrank();
    }

    function test_claim_revert_PriceTriggerNotMet() public {
        PacketConfig[] memory configs = _createPacketConfigsWithPriceTrigger();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        // 设置ETH价格为1500U（低于触发价格）
        vm.mockCall(
            ETH_USD_FEED[block.chainid],
            abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector),
            abi.encode(0, 1500e8, 0, 0, 0)
        );

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 尝试领取应该失败
        vm.startPrank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPacket.TriggerConditionNotMet.selector,
                address(priceTrigger)
            )
        );
        packet.claim(0, proofs);
        vm.stopPrank();
    }

    // 测试随机分发
    function test_claim_with_random_distribution() public {
        PacketConfig[]
            memory configs = _createPacketConfigsWithRandomDistribution();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = codeHash;

        // 多个用户领取
        address[] memory users = new address[](3);
        for (uint i = 0; i < 3; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i.toString())));
            vm.deal(users[i], 1 ether);

            vm.startPrank(users[i]);
            bool success = packet.claim(0, proofs);
            assertTrue(success);
            vm.stopPrank();
        }

        // 验证总金额
        uint256 totalClaimed;
        for (uint i = 0; i < 3; i++) {
            totalClaimed += mockToken.balanceOf(users[i]);
        }
        assertEq(totalClaimed, 100 ether);
    }

    // 测试持有者访问控制
    function test_claim_with_holder_access() public {
        PacketConfig[] memory configs = _createPacketConfigsWithHolderAccess();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = abi.encode("");

        // user2已经有代币，应该可以领取
        vm.startPrank(user2);
        bool success = packet.claim(0, proofs);
        assertTrue(success);
        vm.stopPrank();

        // 创建一个没有代币的用户，应该无法领取
        address user3 = makeAddr("user3");
        vm.startPrank(user3);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPacket.AccessDenied.selector,
                address(holderAccess)
            )
        );
        packet.claim(0, proofs);
        vm.stopPrank();
    }

    // 测试抽奖访问控制
    function test_claim_with_lucky_draw_access() public {
        PacketConfig[]
            memory configs = _createPacketConfigsWithLuckyDrawAccess();
        vm.startPrank(address(factory));
        packet.initialize(configs, user);
        vm.stopPrank();

        // 准备资产
        vm.startPrank(user);
        mockToken.transfer(address(packet), 100 ether);
        vm.stopPrank();

        // 准备访问证明
        bytes[] memory proofs = new bytes[](1);
        proofs[0] = abi.encode("");

        // 多次尝试领取，验证概率
        uint256 successCount;
        uint256 totalAttempts = 100;
        address[] memory users = new address[](totalAttempts);

        for (uint i = 0; i < totalAttempts; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i.toString())));
            vm.deal(users[i], 1 ether);
            vm.startPrank(users[i]);

            try packet.claim(0, proofs) returns (bool success) {
                if (success) successCount++;
            } catch {}

            vm.stopPrank();
        }

        // 验证成功率在合理范围内（设置概率为20%）
        assertApproxEqRel(successCount, (totalAttempts * 20) / 100, 0.3e18); // 允许30%的误差
    }

    function _createPacketConfigs()
        internal
        view
        returns (PacketConfig[] memory configs)
    {
        configs = new PacketConfig[](1);

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

        AccessConfig[] memory access = new AccessConfig[](1);
        access[0] = AccessConfig({
            validator: address(codeAccess),
            data: codeHash
        });

        TriggerConfig[] memory triggers = new TriggerConfig[](0);

        DistributeConfig memory distribute = DistributeConfig({
            distributor: address(fixedDistributor),
            data: ""
        });

        BaseConfig memory base = BaseConfig({
            name: "Test Red Packet",
            message: "Test Message",
            startTime: block.timestamp,
            durationTime: 7 days,
            shares: 1,
            access: access,
            triggers: triggers,
            distribute: distribute
        });

        configs[0] = PacketConfig({base: base, assets: assets});
    }

    function _createPacketConfigsWithPriceTrigger()
        internal
        view
        returns (PacketConfig[] memory configs)
    {
        configs = new PacketConfig[](1);
        configs[0] = _createPacketConfigs()[0];

        // 添加价格触发条件：ETH价格 > 1800U
        TriggerConfig[] memory triggers = new TriggerConfig[](1);
        triggers[0] = TriggerConfig({
            validator: address(priceTrigger),
            data: abi.encode(ETH_USD_FEED[block.chainid], 1800e8, true)
        });

        configs[0].base.triggers = triggers;
    }

    function _createPacketConfigsWithRandomDistribution()
        internal
        view
        returns (PacketConfig[] memory configs)
    {
        configs = new PacketConfig[](1);
        configs[0] = _createPacketConfigs()[0];

        // 使用随机分发
        configs[0].base.distribute = DistributeConfig({
            distributor: address(randomDistributor),
            data: abi.encode(10 ether) // 最小金额为10 ETH
        });

        // 修改份数
        configs[0].base.shares = 3;
    }

    function _createPacketConfigsWithHolderAccess()
        internal
        view
        returns (PacketConfig[] memory configs)
    {
        configs = new PacketConfig[](1);
        configs[0] = _createPacketConfigs()[0];

        // 使用持有者访问控制
        AccessConfig[] memory access = new AccessConfig[](1);
        access[0] = AccessConfig({
            validator: address(holderAccess),
            data: abi.encode(address(mockToken), 100 ether) // 需要持有100个代币
        });

        configs[0].base.access = access;
    }

    function _createPacketConfigsWithLuckyDrawAccess()
        internal
        view
        returns (PacketConfig[] memory configs)
    {
        configs = new PacketConfig[](1);
        configs[0] = _createPacketConfigs()[0];

        // 使用抽奖访问控制
        AccessConfig[] memory access = new AccessConfig[](1);
        access[0] = AccessConfig({
            validator: address(luckyDrawAccess),
            data: abi.encode(20) // 20%的中奖概率
        });

        configs[0].base.access = access;
    }

    receive() external payable {}
}
