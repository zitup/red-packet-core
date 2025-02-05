// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

contract MockAggregatorV3 is IAggregatorV3 {
    uint8 public constant override decimals = 8;
    string public constant override description = "Mock ETH/USD Price Feed";
    uint256 public constant override version = 1;

    int256 private _price;

    constructor() {
        _price = 2000e8; // 默认价格 2000 USD
    }

    function setPrice(int256 price) external {
        _price = price;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, block.timestamp, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }
}
