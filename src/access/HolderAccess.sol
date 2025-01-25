// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;
import "../interfaces/IAccess.sol";
import "../interfaces/types.sol";
import {IERC721} from "@oz/contracts/interfaces/IERC721.sol";
import {IERC20} from "@oz/contracts/interfaces/IERC20.sol";
import {IERC1155} from "@oz/contracts/interfaces/IERC1155.sol";

/// @title HolderValidator
/// @notice Validates if a user holds required amount of tokens
contract HolderAccess is IAccess {
    struct TokenRequirement {
        AssetType tokenType;
        address token;
        uint256 tokenId;
        uint256 minAmount;
    }

    /// @notice Validates if the user meets token holding requirements
    /// @param user The user to validate
    /// @param {data} Unused in token holding validation
    /// @param configData Encoded TokenRequirement
    function validate(
        address user,
        bytes calldata,
        bytes calldata configData
    ) external view returns (bool) {
        TokenRequirement memory requirement = abi.decode(
            configData,
            (TokenRequirement)
        );

        // gas optimization
        AssetType tokenType = requirement.tokenType;
        uint256 minAmount = requirement.minAmount;
        address token = requirement.token;
        uint256 tokenId = requirement.tokenId;

        if (tokenType == AssetType.Native) {
            return user.balance >= minAmount;
        } else if (tokenType == AssetType.ERC20) {
            return IERC20(token).balanceOf(user) >= minAmount;
        } else if (tokenType == AssetType.ERC721) {
            return IERC721(token).balanceOf(user) >= minAmount;
        } else if (tokenType == AssetType.ERC1155) {
            return IERC1155(token).balanceOf(user, tokenId) >= minAmount;
        }

        return false;
    }
}
