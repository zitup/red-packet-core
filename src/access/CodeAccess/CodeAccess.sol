// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../../interfaces/IAccess.sol";
import "./Verifier.sol";

contract CodeAccess is IAccess {
    Groth16Verifier public verifier;

    error InvalidProof();

    constructor(address _verifier) {
        verifier = Groth16Verifier(_verifier);
    }

    function validate(
        address user,
        bytes calldata data,
        bytes calldata configData
    ) external view returns (bool) {
        (uint[2] memory _pA, uint[2][2] memory _pB, uint[2] memory _pC) = abi
            .decode(data, (uint[2], uint[2][2], uint[2]));

        bytes32 codeHash = abi.decode(configData, (bytes32));
        uint256[3] memory pubSingles;
        pubSingles[0] = uint256(codeHash);
        pubSingles[1] = uint256(uint160(msg.sender)); // packet address
        pubSingles[2] = uint256(uint160(user));

        bool success = verifier.verifyProof(_pA, _pB, _pC, pubSingles);
        if (!success) {
            revert InvalidProof();
        }
        return true;
    }
}
