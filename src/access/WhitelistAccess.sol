// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IAccess.sol";

contract WhitelistAccess is IAccess {
    function validate(
        address user,
        bytes calldata,
        bytes calldata configData
    ) external pure returns (bool) {
        address[] memory whitelist = abi.decode(configData, (address[]));
        for (uint i = 0; i < whitelist.length; i++) {
            if (whitelist[i] == user) return true;
        }
        return false;
    }
}
