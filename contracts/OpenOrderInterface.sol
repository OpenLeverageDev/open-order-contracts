// SPDX-License-Identifier: BUSL-1.1
pragma solidity > 0.8.0;

import "./libraries/Order.sol";

interface OpenOrderInterface{
    // output data or extract from transaction?
    event OrderCreated(address indexed owner, uint indexed orderID, bytes32 indexed orderHash, Order.OrderArgs order);
    event OrderCanceled(address indexed owner, uint indexed orderID, Order.OrderArgs order);

    event MarginTradeExecuted(address indexed owner, address indexed executor, uint indexed orderID, Order.OrderArgs order);
    event CloseTradeExecuted(address indexed owner, address indexed executor, uint indexed orderID, Order.OrderArgs order);

    function createMarginLimitOpenETHOrder(Order.OrderArgs calldata _order) external payable returns (uint orderID);

    function cancelMarginLimitOpenETHOrder(Order.OrderArgs calldata _order, uint _orderID) external;

    function revokeNonce(uint _nonce) external;

    function executeMarginLimitOpenETHOrder(Order.OrderArgs calldata _order, uint _orderID) external;

    function executeMarginLimitOpenOrderBySig(address _owner, uint _nonce, Order.OrderArgs calldata _order, bytes calldata _sig) external;

    function executeCreateLimitCloseOrderBySigs(address _owner, uint _nonce, Order.OrderArgs calldata _order, bytes calldata _sig) external;

    function executeCreateLimitStopLossOrderBySigs(address _owner, uint _nonce, Order.OrderArgs calldata _order, bytes calldata _sig) external;
}