// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IAccess.sol";
import {MerkleProof} from "@oz/contracts/utils/cryptography/MerkleProof.sol";

/// @title WhitelistAccess
/// @notice A validator for whitelist-based access control using Merkle tree
contract WhitelistAccess is IAccess {
    /// @notice Validates if the user is in the whitelist using Merkle proof
    /// @param user The user trying to claim the packet
    /// @param proof The Merkle proof
    /// @param configData The Merkle root
    /// @return valid True if the user is in the whitelist
    function validate(
        address user,
        bytes calldata proof,
        bytes calldata configData
    ) external pure returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(user))));

        bytes32[] memory proofs = abi.decode(proof, (bytes32[]));

        return MerkleProof.verify(proofs, bytes32(configData), leaf);
    }
}
