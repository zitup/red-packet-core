// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract CounterScript is Script {
    MockERC20 public mockERC20;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        mockERC20 = new MockERC20{salt: bytes32(uint256(1))}(
            "MockERC20",
            "MockERC20"
        );
        mockERC20.mint(msg.sender, 1000 * 10 ** 18);

        vm.stopBroadcast();
    }
}
