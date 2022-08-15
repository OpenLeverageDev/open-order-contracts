// SPDX-License-Identifier: BUSL-1.1
pragma solidity > 0.7.6;

import "../interfaces/OpenLevInterface.sol";
import "../interfaces/DexAggregatorInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

pragma experimental ABIEncoderV2;


contract MockDexAgg is DexAggregatorInterface {
    uint8 private constant _decimals = 18;
    uint private _price;
    uint private _cAvgPrice;
    uint private _hAvgPrice;
    uint private _timestamp;


    function setPrice(uint price_, uint cAvgPrice_, uint hAvgPrice_, uint timestamp_) external {
        _price = price_;
        _cAvgPrice = cAvgPrice_;
        _hAvgPrice = hAvgPrice_;
        _timestamp = timestamp_;
    }

    function getPrice(address desToken, address quoteToken, bytes memory data) external override view
    returns (uint256 price, uint8 decimals){
        price = _price;
        decimals = _decimals;
    }

    function getPriceCAvgPriceHAvgPrice(address desToken, address quoteToken, uint32 secondsAgo, bytes memory dexData) external override view
    returns (uint price, uint cAvgPrice, uint256 hAvgPrice, uint8 decimals, uint256 timestamp){
        price = _price;
        cAvgPrice = _cAvgPrice;
        hAvgPrice = _hAvgPrice;
        decimals = _decimals;
        timestamp = _timestamp;
    }

    function updatePriceOracle(address desToken, address quoteToken, uint32 timeWindow, bytes memory data) external override returns (bool){
        return true;
    }


}