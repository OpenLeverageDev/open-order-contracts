// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import "./interfaces/DexAggregatorInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./libraries/Order.sol";
import "./libraries/TransferHelper.sol";

contract OpenOrder{
    using Order for Order.OrderArgs;
    using TransferHelper for IERC20;

    uint immutable MILLION = 10**6;
    uint immutable QUINTILLION = 18;

    uint32 public minTimeOfAvgPrice;
    uint public allowedSlippage;
    address public nativeToken;
    address public openLeverage;
    address public dexAggregator;

    uint public lastOrderID;

    // mapping(uint => uint) public shares;  // mapping orderID => share
    mapping(address => mapping(uint => bool)) public invalidNonces;
    mapping(bytes32 => address) public ownerOfEthOrder;

    // output data or extract from transaction?
    event OrderCreated(address indexed owner, uint indexed orderID, bytes32 indexed orderHash, Order.OrderArgs order);
    event OrderCanceled(address indexed owner, uint indexed orderID, Order.OrderArgs order);
    event MarginTradeExecuted(address indexed owner, address indexed executor, uint indexed orderID, Order.OrderArgs order);
    event CloseTradeExecuted(address indexed owner, address indexed executor, uint indexed orderID, Order.OrderArgs order);

    constructor(uint32 _minTimeOfAvgPrice, uint _allowedSlippage, address _nativeToken){
        minTimeOfAvgPrice = _minTimeOfAvgPrice;
        allowedSlippage = _allowedSlippage;
        nativeToken = _nativeToken;
    }

    modifier ensure(uint expiryTime) {
        require(expiryTime >= block.timestamp, 'OpenOrder:EXPIRED');
        _;
    }

    function createMarginLimitOpenETHOrder(Order.OrderArgs calldata _order) external payable ensure(_order.expiryTime) returns (uint orderID) {       
        require(_order.orderType == Order.TYPE_MARGIN_LIMIT_OPEN, "OpenOrder:NOT SPOT TRADE");
        require(_order.depositToken == nativeToken, "OpenOrder:ONLY NATIVE");

        Order.MarginTradeArgs memory marginTradeParams = _order.decodeMarginTradeParams();
        require(marginTradeParams.deposit + _order.commission == msg.value, "OpenOrder:INSIFFICIENT DEPOSIT");

        orderID = ++lastOrderID;
        bytes32 orderHash = _order.orderHash(orderID);
        ownerOfEthOrder[orderHash] = msg.sender;

        emit OrderCreated(msg.sender, orderID, orderHash, _order);
    }

    function cancelMarginLimitOpenETHOrder(Order.OrderArgs calldata _order, uint _orderID) external ensure(_order.expiryTime) {
        require(_order.orderType == Order.TYPE_MARGIN_LIMIT_OPEN, "OpenOrder:WRONG ORDER TYPE");
        
        bytes32 orderHash = _order.orderHash(_orderID);
        require(ownerOfEthOrder[orderHash] == msg.sender, "OpenOrder:UNAUTHORIZED");

        ownerOfEthOrder[orderHash] = address(0);

        Order.MarginTradeArgs memory marginTradeParams = _order.decodeMarginTradeParams();
        _pay(msg.sender, _order.depositToken, marginTradeParams.deposit);

        emit OrderCanceled(msg.sender, _orderID, _order);
    }

    // recommand using timestamp for _nonce
    function revokeNonce(uint _nonce) external{
        // require(!invalidNonces[msg.sender][_nonce], "OpenOrder:NONCE REVOKED");
        invalidNonces[msg.sender][_nonce] = true;
    }

    function executeMarginLimitOpenETHOrder(Order.OrderArgs calldata _order, uint _orderID) external ensure(_order.expiryTime) {
        require(_order.orderType == Order.TYPE_MARGIN_LIMIT_OPEN, "OpenOrder:NOT MARGIN LIMIT OPEN");
        
        bytes32 orderHash = _order.orderHash(_orderID);
        address orderOwner = ownerOfEthOrder[orderHash];
        
        require(orderOwner != address(0), "OpenOrder:ORDER NOT EXISTS");

        ownerOfEthOrder[orderHash] = address(0);

        _executeMarginLimitOpenOrder(orderOwner, _order, _orderID);
    }

    function executeMarginLimitOpenOrderBySig(address _owner, uint _nonce, Order.OrderArgs calldata _order, bytes calldata _sig) external payable ensure(_order.expiryTime){
        require(!invalidNonces[_owner][_nonce], "OpenOrder:NONCE REVOKED");
        require(SignatureChecker.isValidSignatureNow(_owner, _order.orderHash(_nonce), _sig), "OpenOrder:INVALID SIGNATURE");

        invalidNonces[_owner][_nonce] = true;
        
        _executeMarginLimitOpenOrder(_owner, _order, 0);
    }

    function executeCreateLimitCloseOrderBySigs(address _owner, uint _nonce, Order.OrderArgs calldata _order, bytes calldata _sig) external payable ensure(_order.expiryTime){
        require(!invalidNonces[_owner][_nonce], "OpenOrder:NONCE REVOKED");
        require(SignatureChecker.isValidSignatureNow(_owner, _order.orderHash(_nonce), _sig), "OpenOrder:INVALID SIGNATURE");

        invalidNonces[_owner][_nonce] = true;
        
        _executeCreateLimitCloseOrder(_owner, _order, 0);
    }

    function executeCreateLimitStopLossOrderBySigs(address _owner, uint _nonce, Order.OrderArgs calldata _order, bytes calldata _sig) external payable ensure(_order.expiryTime){
        require(!invalidNonces[_owner][_nonce], "OpenOrder:NONCE REVOKED");
        require(SignatureChecker.isValidSignatureNow(_owner, _order.orderHash(_nonce), _sig), "OpenOrder:INVALID SIGNATURE");

        invalidNonces[_owner][_nonce] = true;
        
        _executeCreateLimitCloseOrder(_owner, _order, 0);
    }

    function _executeMarginLimitOpenOrder(address orderOwner, Order.OrderArgs calldata _order, uint _orderID) internal {
        // get Price
        Order.MarginTradeArgs memory marginTradeParams = _order.decodeMarginTradeParams();
        OpenLevInterface.Market memory market = OpenLevInterface(openLeverage).markets(marginTradeParams.marketId);
        (address depositToken, address quoteToken) = marginTradeParams.depositToken ? (market.token1, market.token0) : (market.token0, market.token1);
        uint avgPrice = _avgPriceOf(depositToken, quoteToken, marginTradeParams.dexData);
        require(avgPrice <= _order.limitPrice, "OpenOrder:INVALID EXECUTION");

        // call marginTrade
        _callOpenLeverage(_order.callArgs, depositToken == nativeToken ? marginTradeParams.deposit : 0);
        _pay(msg.sender, depositToken, _order.commission);
        
        emit MarginTradeExecuted(orderOwner, msg.sender, _orderID, _order);
    }

    function _executeCreateLimitCloseOrder(address orderOwner, Order.OrderArgs calldata _order, uint _orderID) internal{
        // get Price
        Order.CloseTradeArgs memory closeTradeParams = _order.decodeCloseTradeParams();
        OpenLevInterface.Market memory market = OpenLevInterface(openLeverage).markets(closeTradeParams.marketId);
        OpenLevInterface.Trade memory trade = OpenLevInterface(openLeverage).activeTrades( closeTradeParams.holder, closeTradeParams.marketId, closeTradeParams.longToken);
        (address depositToken, address quoteToken) = trade.depositToken ? (market.token1, market.token0) : (market.token0, market.token1);
        uint avgPrice = _avgPriceOf(depositToken, quoteToken, closeTradeParams.dexData);
        require(avgPrice >= _order.limitPrice, "OpenOrder:INVALID EXECUTION");

        // call marginTrade
        _callOpenLeverage(_order.callArgs, 0);
        _pay(msg.sender, depositToken, _order.commission);

        emit CloseTradeExecuted(orderOwner, msg.sender, _orderID, _order);
    }

    function _executeCreateLimitStopLossOrder(address orderOwner, Order.OrderArgs calldata _order, uint _orderID) internal{
        // get Price
        Order.CloseTradeArgs memory closeTradeParams = _order.decodeCloseTradeParams();
        OpenLevInterface.Market memory market = OpenLevInterface(openLeverage).markets(closeTradeParams.marketId);
        OpenLevInterface.Trade memory trade = OpenLevInterface(openLeverage).activeTrades( closeTradeParams.holder, closeTradeParams.marketId, closeTradeParams.longToken);
        (address depositToken, address quoteToken) = trade.depositToken ? (market.token1, market.token0) : (market.token0, market.token1);
        uint avgPrice = _avgPriceOf(depositToken, quoteToken, closeTradeParams.dexData);
        uint currentPrice = _currentPriceOf(depositToken, quoteToken, closeTradeParams.dexData);
        require(avgPrice <= _order.limitPrice && currentPrice > avgPrice * allowedSlippage / MILLION, "OpenOrder:INVALID EXECUTION");

        // call marginTrade
        _callOpenLeverage(_order.callArgs, 0);
        _pay(msg.sender, depositToken, _order.commission);

        emit CloseTradeExecuted(orderOwner, msg.sender, _orderID, _order);
    }

    function _callOpenLeverage(bytes memory _data, uint _amount) internal{
        (bool success, ) = address(openLeverage).call{value: _amount}(_data);
        require(success, "OpenOrder:CONTRACT CALL FAILED");
    }

    function _collect(address _token, address _from, uint _amount) internal returns (uint){
        if (_token != nativeToken){
            return IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        }else{
            require(_amount == msg.value, "OpenOrder:WRONG AMOUNT DEPOSITED");
            return msg.value;
        }
    }

    function _collectAtNewOrder(address _depositToken, uint _deposit, uint _commission) internal returns (uint deposit, uint commission){
        uint toCollect = _deposit + _commission;
        uint collected = _collect(_depositToken, msg.sender, toCollect);

        deposit = collected * _deposit / toCollect;
        commission = commission * _commission / toCollect;
    }

    function _pay(address _to, address _token, uint _amount) internal returns (uint){
        if (_token != nativeToken){
            return IERC20(_token).safeTransfer(_to, _amount);
        }else{
            (bool success, ) = _to.call{value: _amount}("");
            require(success);
            return _amount;
        }
    }

    function _balanceOf(address _token, address _owner) internal view returns (uint){
        if (_token != nativeToken){
            return IERC20(_token).balanceOf(_owner);
        }else{
            return _owner.balance;
        }
    }

    function _avgPriceOf(address _desToken, address _quoteToken, bytes memory _dexData) internal view returns(uint avgPrice){
        uint8 decimals;
        (avgPrice, decimals, ) = DexAggregatorInterface(dexAggregator).getAvgPrice(_desToken, _quoteToken, minTimeOfAvgPrice, _dexData); 

        return decimals < QUINTILLION ? avgPrice * 10 ** (QUINTILLION - decimals) : avgPrice / (10 ** (decimals - QUINTILLION));
    }

    function _currentPriceOf(address _desToken, address _quoteToken, bytes memory _dexData) internal view returns(uint avgPrice){
        uint8 decimals;
        (avgPrice, decimals) = DexAggregatorInterface(dexAggregator).getPrice(_desToken, _quoteToken, _dexData); 

        return decimals < QUINTILLION ? avgPrice * 10 ** (QUINTILLION - decimals) : avgPrice / (10 ** (decimals - QUINTILLION));
    }
}