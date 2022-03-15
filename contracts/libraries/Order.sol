// SPDX-License-Identifier: BUSL-1.1
pragma solidity > 0.8.0;

import "../interfaces/OpenLevInterface.sol";

library Order{

    struct SpotTradeArgs{
        address depositToken;
        uint deposit;
        address withdrawToken;
    }

    struct MarginTradeArgs{
        address holder;
        uint16 marketId;
        bool longToken;
        bool depositToken;
        uint deposit;
        uint borrow;
        uint minBuyAmount;
        bytes dexData;
    }

    struct CloseTradeArgs{
        address holder;
        uint16 marketId;
        bool longToken; 
        uint closeHeld;
        uint minOrMaxAmount;
        bytes dexData;
    }

    struct OrderArgs{
        address commisionToken;
        uint commision;
        uint deadline;
        uint triggerBelow;
        uint triggerAbove;
        bytes callArgs;
    }

    function isMarginTrade(OrderArgs calldata _order) internal pure returns (bool) {
        return bytes4(_order.callArgs[:4]) == OpenLevInterface.marginTradeFor.selector;
    }

    function isCloseTrade(OrderArgs calldata _order) internal pure returns (bool) {
        return bytes4(_order.callArgs[:4]) == OpenLevInterface.closeTrade.selector;
    }

    function decodeSpotTradeParams(OrderArgs calldata _order) internal pure returns (SpotTradeArgs memory params){
        (
           params.depositToken,
           params.deposit,
           params.withdrawToken
       ) = abi.decode(_order.callArgs[4:], (address, uint, address));
    }

    function decodeMarginTradeParams(OrderArgs calldata _order) internal pure returns (MarginTradeArgs memory params){
       (
           params.holder,
           params.marketId,
           params.longToken,
           params.depositToken,
           params.deposit,
           params.borrow,
           params.minBuyAmount,
           params.dexData
       ) = abi.decode(_order.callArgs[4:], (address, uint16, bool, bool, uint, uint, uint, bytes));
    }

    function decodeCloseTradeParams(OrderArgs calldata _order) internal pure returns (CloseTradeArgs memory params){
        (
           params.holder,
           params.marketId,
           params.longToken,
           params.closeHeld,
           params.minOrMaxAmount,
           params.dexData
       ) = abi.decode(_order.callArgs[4:], (address, uint16, bool, uint, uint, bytes));
    }
    
    function setSpotTradeParams(OrderArgs memory _order, SpotTradeArgs memory _params, uint _commision) internal pure returns (OrderArgs memory){
        _order.commision = _commision;
        _order.callArgs = abi.encode(
            _params.depositToken,
            _params.deposit,
            _params.withdrawToken
        );

        return _order;
    }
    
    function setMarginTradeParams(OrderArgs memory _order, MarginTradeArgs memory _params, uint _commision) public pure returns (OrderArgs memory){
        _order.commision = _commision;
        _order.callArgs = abi.encodePacked(
            OpenLevInterface.marginTradeFor.selector,
            abi.encode(
                _params.holder,
                _params.marketId,
                _params.longToken,
                _params.depositToken,
                _params.deposit,
                _params.borrow,
                _params.minBuyAmount,
                _params.dexData
            )
        );

        return _order;
    }

    function setCloseTradeParams(OrderArgs memory _order, uint _commision) internal pure returns (OrderArgs memory){
        _order.commision = _commision;
        return _order;
    }
}