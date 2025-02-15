// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC721} from "@oz/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }
}
