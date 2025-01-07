// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IAccess.sol";

contract CodeAccess is IAccess {
    // 预留ZK验证的数据结构
    struct ZKProofData {
        uint256[] publicInputs;
        uint256[] proof;
    }

    function validate(
        address,
        bytes calldata data,
        bytes calldata configData
    ) external pure returns (bool) {
        bytes32 inputHash = abi.decode(data, (bytes32));
        bytes32 codeHash = abi.decode(configData, (bytes32));
        return codeHash == inputHash;
    }
}
