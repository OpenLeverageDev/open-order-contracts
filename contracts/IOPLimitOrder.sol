// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "./interfaces/DexAggregatorInterface.sol";
import "./interfaces/OpenLevInterface.sol";
import "./IOPLimitOrder.sol";
import "./IOPLimitOrder.sol";

abstract contract OPLimitOrderStorage {

    struct Order {
        uint256 salt;
        address owner;
        uint32 deadline;
        uint16 marketId;
        bool longToken;
        bool depositToken;
        address commissionToken;
        uint256 commission;
        uint256 price0;// scale 10**18
    }

    struct OpenOrder {
        uint256 salt;
        address owner;
        uint32 deadline;
        uint16 marketId;
        bool longToken;
        bool depositToken;
        address commissionToken;
        uint256 commission;
        uint256 price0;// scale 10**18

        uint256 deposit;
        uint256 borrow;
        uint256 expectHeld;
    }

    struct CloseOrder {
        uint256 salt;
        address owner;
        uint32 deadline;
        uint16 marketId;
        bool longToken;
        bool depositToken;
        address commissionToken;
        uint256 commission;
        uint256 price0;// scale 10**18

        bool isStopLose;
        uint256 closeHeld;
        uint256 expectReturn;
    }

    bytes32 constant public ORDER_TYPEHASH = keccak256(
        "Order(uint256 salt,address owner,uint32 deadline,uint16 marketId,bool longToken,bool depositToken,address commissionToken,uint256 commission,uint256 price0)"
    );
    bytes32 constant public OPEN_ORDER_TYPEHASH = keccak256(
        "OpenOrder(uint256 salt,address owner,uint32 deadline,uint16 marketId,bool longToken,bool depositToken,address commissionToken,uint256 commission,uint256 price0,uint256 deposit,uint256 borrow,uint256 expectHeld)"
    );
    bytes32 constant public CLOSE_ORDER_TYPEHASH = keccak256(
        "CloseOrder(uint256 salt,address owner,uint32 deadline,uint16 marketId,bool longToken,bool depositToken,address commissionToken,uint256 commission,uint256 price0,bool isStopLose,uint256 closeHeld,uint256 expectReturn)"
    );

    OpenLevInterface public openLev;
    DexAggregatorInterface public dexAgg;

    event OrderCanceled(address indexed trader, bytes32 orderId, uint256 remaining);

    event OrderFilled(address indexed trader, bytes32 orderId, uint256 commission, uint256 remaining, uint256 filling);


}

interface IOPLimitOrder {

    function fillOpenOrder(OPLimitOrderStorage.OpenOrder memory order, bytes calldata signature, uint256 fillingDeposit, bytes memory dexData) external;

    function fillCloseOrder(OPLimitOrderStorage.CloseOrder memory order, bytes calldata signature, uint256 fillingHeld, bytes memory dexData) external;

    function closeTradeAndCancel(uint16 marketId, bool longToken, uint closeHeld, uint minOrMaxAmount, bytes memory dexData, OPLimitOrderStorage.Order[] memory orders) external;

    function cancelOrder(OPLimitOrderStorage.Order memory order) external;

    function cancelOrders(OPLimitOrderStorage.Order[] memory orders) external;

    function remaining(bytes32 _orderId) external view returns (uint256);

    function remainingRaw(bytes32 _orderId) external view returns (uint256);

    function orderId(OPLimitOrderStorage.Order memory order) external view returns (bytes32);

    function hashOpenOrder(OPLimitOrderStorage.OpenOrder memory order) external view returns (bytes32);

    function hashCloseOrder(OPLimitOrderStorage.CloseOrder memory order) external view returns (bytes32);

}