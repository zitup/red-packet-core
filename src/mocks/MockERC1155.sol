// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC1155} from "@oz/contracts/token/ERC1155/ERC1155.sol";

contract MockERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external {
        _mint(to, id, amount, data);
    }

    function mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) external {
        _mintBatch(to, ids, amounts, data);
    }
}
