// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IAccess.sol";

contract AccessValidatorTemplate is IAccess {
    function validate(
        address user,
        bytes calldata data,
        bytes calldata configData
    ) external pure returns (bool) {
        bytes32 codeHash = abi.decode(configData, (bytes32));
        bytes32 inputHash = keccak256(data);
        return codeHash == inputHash;
    }
}
