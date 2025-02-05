// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ITrigger} from "../interfaces/ITrigger.sol";

import {IAggregatorV3} from "../interfaces/IAggregatorV3.sol";

/// @title PriceTrigger
/// @notice Validates if token price meets the requirement
contract PriceTrigger is ITrigger {
    /// @notice Unused for now. Heart beat duration(seconds) of price feed, according to https://docs.chain.link/data-feeds/price-feeds/addresses
    // uint256 public priceFeedHeartbeat;
    /// @notice L2 Sequencer feed, according to https://docs.chain.link/data-feeds/l2-sequencer-feeds
    IAggregatorV3 immutable sequencer;
    /// @notice L2 Sequencer grace period
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    /// @notice Thrown when the days of duration is less then MINIMUM_DURATION
    error InvalidDuration();
    /// @notice Thrown when the feed price is less then or equal 0
    error InvalidFeedPrice(int256 price);
    /// @notice Thrown when the feed price is staled
    error StaledPriceFeed(uint256 timeStamp);
    /// @notice Thrown when the L2 sequencer is unactive
    error L2SequencerUnavailable();
    /// @notice Thrown when the feed price exceed the acceptable price
    error ExceedAcceptablePrice(uint256 price);
    error InvalidOracle();

    enum Condition {
        GreaterThan,
        LessThan,
        InRange
    }

    struct PriceCondition {
        address oracle;
        Condition condition;
        uint256 price; // with oracle decimal. Price * 10 ** priceFeed.decimals()
        uint256 upperBound;
    }

    constructor(address _sequencer) {
        sequencer = IAggregatorV3(_sequencer);
    }

    function validate(bytes calldata triggerData) external view returns (bool) {
        PriceCondition memory condition = abi.decode(
            triggerData,
            (PriceCondition)
        );

        if (condition.oracle == address(0)) revert InvalidOracle();

        uint256 currentPrice = _getChainlinkPrice(condition.oracle);

        if (condition.condition == Condition.GreaterThan) {
            return currentPrice > condition.price;
        } else if (condition.condition == Condition.LessThan) {
            return currentPrice < condition.price;
        } else if (condition.condition == Condition.InRange) {
            return
                currentPrice >= condition.price &&
                currentPrice <= condition.upperBound;
        }

        return false;
    }

    function _getChainlinkPrice(
        address priceFeed
    ) internal view returns (uint256) {
        _isSequencerUp();

        // prettier-ignore
        (
            /* uint80 roundID */,
            int256 _price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = IAggregatorV3(priceFeed).latestRoundData();

        if (_price <= 0) {
            revert InvalidFeedPrice(_price);
        }

        // if (block.timestamp - timeStamp > priceFeedHeartbeat) {
        //     revert StaledPriceFeed(timeStamp);
        // }
        return uint256(_price);
    }

    function _isSequencerUp() internal view {
        if (address(sequencer) == address(0)) {
            return;
        }

        (, int256 answer, uint256 startedAt, , ) = sequencer.latestRoundData();
        if (block.timestamp - startedAt <= GRACE_PERIOD_TIME || answer == 1)
            revert L2SequencerUnavailable();
    }
}
