// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import "./interfaces/DexAggregatorInterface.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./libraries/Order.sol";
import "./libraries/TransferHelper.sol";

contract OpenOrder is ERC721{
    using Order for Order.OrderArgs;
    using TransferHelper for IERC20;

    uint immutable decimals = 18;
    uint public lastOrderID;
    address public nativeToken;

    address public openLeverage;
    address public dexAggregator;
    uint32 avgPriceGap;

    // output data or extract from transaction?
    event OrderCreated(address indexed owner, uint indexed orderID, uint indexed orderHash, Order.OrderArgs order);
    event OrderCanceled(address indexed owner, uint indexed orderID, Order.OrderArgs order);
    event SpotTradeExecuted(
        address indexed owner, 
        address indexed executor,
        uint indexed orderID, 
        Order.OrderArgs order,
        uint amountWithdrawed,
        address callTarget,
        uint _amount, 
        bytes _data
    );
    event MarginTradeExecuted(address indexed owner, address indexed executor, uint indexed orderID, Order.OrderArgs order);
    event CloseTradeExecuted(address indexed owner, address indexed executor, uint indexed orderID, Order.OrderArgs order);

    constructor(uint32 _avgPriceGap) ERC721("Open Order", "OO"){
        avgPriceGap = _avgPriceGap;
    }

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'OpenOrder: EXPIRED');
        _;
    }

    function createOrders(Order.OrderArgs[] calldata _orders) external payable returns (uint[] memory orderIDs) {
        orderIDs = new uint[](_orders.length);
        for (uint i; i < _orders.length; i++){
            orderIDs[i] = createOrder(_orders[i]);
        }
    }

    function cancelOrders(Order.OrderArgs[] calldata _orders, uint[] memory _nonces) external {
        for (uint i; i < _orders.length; i++){
            cancelOrder(_orders[i], _nonces[i]);
        }
    }

    /// @dev call ERC20(_callTarget).transferFrom(from, to, amount) to collect deposit token.
    function executeSpotTrade(Order.OrderArgs calldata _order, uint _orderID, address _callTarget, uint _amount, bytes calldata _data) external payable ensure(_order.deadline){
        uint orderHash = uint256(keccak256(abi.encode(_order, _orderID)));
        // unstake NFT if needed

        address orderOwner = ownerOf(orderHash);
        require(orderOwner != address(0), "OpenOrder: ORDER NOT EXISTS");

        _burn(orderHash);

        Order.SpotTradeArgs memory spotTradeParams = _order.decodeSpotTradeParams();

        uint amountToWithdraw = swap(spotTradeParams, _callTarget, _data);       
        amountToWithdraw += collect(spotTradeParams.withdrawToken, _amount);
        require(avgPrice <= _order.triggerBelow && avgPrice >= _order.triggerAbove, "OpenOrder: INVALID EXECUTION");

        pay(orderOwner, spotTradeParams.withdrawToken, amountToWithdraw);
        pay(msg.sender, _order.commisionToken, _order.commision);

        emit SpotTradeExecuted(
            orderOwner,
            msg.sender,
            _orderID,
            _order,
            amountToWithdraw,
            _callTarget,
            _amount,
            _data
        );
    }

    function executeMarginTrade(Order.OrderArgs calldata _order, uint _orderID) external ensure(_order.deadline) {
        require(_order.isMarginTrade(), "OpenOrder: NOT MARGIN TRADE");
        uint orderHash = uint256(keccak256(abi.encode(_order, _orderID)));
        
        // unstake NFT here if needed

        address orderOwner = ownerOf(orderHash);
        require(orderOwner != address(0), "OpenOrder: ORDER NOT EXISTS");

        _burn(orderHash);

        // get Price
        Order.MarginTradeArgs memory marginTradeParams = _order.decodeMarginTradeParams();
        OpenLevInterface.Market memory market = OpenLevInterface(openLeverage).markets(marginTradeParams.marketId);
        uint avgPrice = avgPriceOf(marginTradeParams.depositToken, market, marginTradeParams.dexData) ;
        require(avgPrice <= _order.triggerBelow && avgPrice >= _order.triggerAbove, "OpenOrder: INVALID EXECUTION");

        // call marginTrade
        callOpenLeverage(_order.callArgs, (marginTradeParams.depositToken ? market.token1 == nativeToken : market.token0 == nativeToken) ? marginTradeParams.deposit : 0);
        pay(msg.sender, _order.commisionToken, _order.commision);
        
        emit MarginTradeExecuted(orderOwner, msg.sender, _orderID, _order);
    }

    function executeCloseTrade(Order.OrderArgs calldata _order, uint _orderID) external {
        require(_order.isCloseTrade(), "OpenOrder: NOT CLOSE TRADE");
        uint orderHash = uint256(keccak256(abi.encode(_order, _orderID)));

        // unstake NFT here if needed

        address orderOwner = ownerOf(orderHash);
        require(orderOwner != address(0), "OpenOrder: ORDER NOT EXISTS");

        _burn(orderHash);

        // get Price
        Order.CloseTradeArgs memory closeTradeParams = _order.decodeCloseTradeParams();
        OpenLevInterface.Market memory market = OpenLevInterface(openLeverage).markets(closeTradeParams.marketId);
        OpenLevInterface.Trade memory trade = OpenLevInterface(openLeverage).activeTrades( closeTradeParams.holder, closeTradeParams.marketId, closeTradeParams.longToken);
        uint avgPrice = avgPriceOf(marginTradeParams.depositToken, market, marginTradeParams.dexData) ;
        require(avgPrice <= _order.triggerBelow && avgPrice >= _order.triggerAbove, "OpenOrder: INVALID EXECUTION");

        // call marginTrade
        callOpenLeverage(_order.callArgs, 0);
        pay(msg.sender, _order.commisionToken, _order.commision);

        emit CloseTradeExecuted(orderOwner, msg.sender, _orderID, _order);
    }

    function createOrder(Order.OrderArgs calldata _order) public returns (uint orderID) {        
        uint commision = collect(_order.commisionToken, _order.commision);
        Order.OrderArgs memory order;

        if (_order.isMarginTrade()){
            Order.MarginTradeArgs memory marginTradeParams = _order.decodeMarginTradeParams();
            OpenLevInterface.Market memory market = OpenLevInterface(openLeverage).markets(marginTradeParams.marketId);
            marginTradeParams.deposit = collect(marginTradeParams.depositToken ? market.token1 : market.token0, marginTradeParams.deposit);
            order = order.setMarginTradeParams(marginTradeParams, commision);
        }else if (_order.isCloseTrade()){
            order = _order.setCloseTradeParams(commision);
        }else{
            Order.SpotTradeArgs memory spotTradeParams = _order.decodeSpotTradeParams();
            spotTradeParams.deposit = collect(spotTradeParams.depositToken, spotTradeParams.deposit);
            order = order.setSpotTradeParams(spotTradeParams, commision);
        }

        orderID = lastOrderID++;
        uint orderHash = uint(keccak256(abi.encode(_order, orderID)));
        _mint(msg.sender, orderHash);

        // stake NFT here if needed

        emit OrderCreated(msg.sender, orderID, orderHash, order);
    }

    // ensure dedaline or not?
    function cancelOrder(Order.OrderArgs calldata _order, uint _orderID) public ensure(_order.deadline) {
        uint orderHash = uint256(keccak256(abi.encode(_order, _orderID)));
        require(ownerOf(orderHash) == msg.sender, "OpenOrder: UNAUTHORIZED");

        // unstake NFT here if needed

        _burn(orderHash);
        if (_order.isMarginTrade()){
            Order.MarginTradeArgs memory marginTradeParams = _order.decodeMarginTradeParams();
            OpenLevInterface.Market memory market = OpenLevInterface(openLeverage).markets(marginTradeParams.marketId);
            pay(msg.sender, marginTradeParams.depositToken ? market.token1 : market.token0, marginTradeParams.deposit);
        }else if (!_order.isCloseTrade()){
            Order.SpotTradeArgs memory spotTradeParams = _order.decodeSpotTradeParams();
            pay(msg.sender, spotTradeParams.depositToken, spotTradeParams.deposit);
        }

        emit OrderCanceled(msg.sender, _orderID, _order);
    }

    function swap(Order.SpotTradeArgs memory _args, address _callTarget, bytes memory _data) internal returns (uint){
        uint balanceBefore = balanceOf(_args.withdrawToken, address(this));
        
        if(_args.depositToken != nativeToken){
            IERC20(_args.depositToken).safeApprove(_callTarget, _args.deposit);
            (bool success, ) = address(_callTarget).call(_data);
            require(success && IERC20(_args.depositToken).allowance(address(this), _callTarget) == 0, "OpenOrder: CONTRACT CALL FAILED");
        }else{
            (bool success, ) = address(_callTarget).call{value: _args.deposit}(_data);
            require(success, "OpenOrder: CONTRACT CALL FAILED");
        }

        return balanceOf(_args.withdrawToken, address(this)) - balanceBefore;
    }

    function callOpenLeverage(bytes memory _data, uint _amount) internal{
        (bool success, ) = address(openLeverage).call{value: _amount}(_data);
        require(success, "OpenOrder: CONTRACT CALL FAILED");
    }

    function collect(address _token, uint _amount) internal returns (uint){
        if (_token != nativeToken){
            return IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        }else{
            require(_amount == msg.value, "OpenOrder: WRONG AMOUNT DEPOSITED");
            return msg.value;
        }
    }

    function pay(address _transferTo, address _token, uint _amount) internal returns (uint){
        if (_token != nativeToken){
            return IERC20(_token).safeTransfer(_transferTo, _amount);
        }else{
            (bool success, ) = _transferTo.call{value: _amount}("");
            require(success);
            return _amount;
        }
    }

    function balanceOf(address _token, address _owner) internal view returns (uint){
        if (_token != nativeToken){
            return IERC20(_token).balanceOf(_owner);
        }else{
            return _owner.balance;
        }
    }

    function avgPriceOf(bool _desToken, OpenLevInterface.Market memory _market, bytes memory _dexData) internal view returns(uint avgPrice){
        uint8 d;
        if(_desToken){
            (avgPrice, d, ) = DexAggregatorInterface(dexAggregator).getAvgPrice(_market.token0, _market.token1, avgPriceGap, _dexData); 
        }else{
            (avgPrice, d, ) = DexAggregatorInterface(dexAggregator).getAvgPrice(_market.token1, _market.token0, avgPriceGap, _dexData);
        }
        
        return d < decimals ? avgPrice * 10 ** (decimals - d) : avgPrice / (10 ** (d - decimals));
    }
}