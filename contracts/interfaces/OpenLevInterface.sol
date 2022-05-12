// SPDX-License-Identifier: BUSL-1.1
pragma solidity > 0.7.6;

pragma experimental ABIEncoderV2;

/**
  * @title OpenLevInterface
  * @author OpenLeverage
  */
interface OpenLevInterface {
    struct Market {// Market info
        address pool0;       // Lending Pool 0
        address pool1;       // Lending Pool 1
        address token0;              // Lending Token 0
        address token1;              // Lending Token 1
        uint16 marginLimit;         // Margin ratio limit for specific trading pair. Two decimal in percentage, ex. 15.32% => 1532
        uint16 feesRate;            // feesRate 30=>0.3%
        uint16 priceDiffientRatio;
        address priceUpdater;
        uint pool0Insurance;        // Insurance balance for token 0
        uint pool1Insurance;        // Insurance balance for token 1
        uint32[] dexs;
    }

    struct Trade {// Trade storage
        uint deposited;             // Balance of deposit token
        uint held;                  // Balance of held position
        bool depositToken;          // Indicate if the deposit token is token 0 or token 1
        uint128 lastBlockNum;       // Block number when the trade was touched last time, to prevent more than one operation within same block
    }

    function activeTrades(address holder, uint16 marketId, bool long) external view returns(Trade memory trade);
    function markets(uint16 marketId) external view returns(Market memory market);
    function marginTradeFor(address holder, uint16 marketId, bool longToken, bool depositToken, uint deposit, uint borrow, uint minBuyAmount, bytes memory dexData) external payable;
    function closeTradeByOpenOrder(address holder, uint16 marketId, bool longToken, uint closeHeld, uint minOrMaxAmount, bytes memory dexData) external;
}
