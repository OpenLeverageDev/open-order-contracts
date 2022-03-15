// SPDX-License-Identifier: BUSL-1.1

pragma solidity > 0.7.6;
pragma experimental ABIEncoderV2;

interface DexAggregatorInterface {
    function getAvgPrice(address desToken, address quoteToken, uint32 secondsAgo, bytes memory data) external view returns (uint256 price, uint8 decimals, uint256 timestamp);
}

