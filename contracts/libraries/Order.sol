// SPDX-License-Identifier: BUSL-1.1
pragma solidity > 0.8.0;

import "../interfaces/OpenLevInterface.sol";

library Order{
    uint constant TYPE_MARGIN_LIMIT_OPEN = 1;
    uint constant TYPE_LIMIT_CLOSE = 2;
    uint constant TYPE_LIMIT_STOP_LOSS = 3;

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
        address depositToken;
        uint orderType;
        uint commission;
        uint expiryTime;
        uint limitPrice;
        bytes32 linkTo;
        bytes callArgs;
    }

    bytes32 constant public ORDERARGS_TYPEHASH = keccak256(
        "OrderArgs(address commissionToken,uint256 commission,uint256 expireTime,uint256 triggerBelow,uint256 triggerAbove,bytes callArgs)"
    );  
    
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

    function orderHash(OrderArgs memory _order,  uint _nonce) internal view returns (bytes32){
        return keccak256(abi.encode(block.chainid, _order, _nonce));
    }
}