// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IAccess.sol";
import {IERC721} from "@oz/contracts/interfaces/IERC721.sol";

contract NFTHolderAccess is IAccess {
    function validate(
        address user,
        bytes calldata,
        bytes calldata configData
    ) external view returns (bool) {
        (address nft, uint256 minBalance) = abi.decode(
            configData,
            (address, uint256)
        );
        return IERC721(nft).balanceOf(user) >= minBalance;
    }
}
