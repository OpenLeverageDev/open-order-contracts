// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/TransferHelper.sol";
import "./DelegateInterface.sol";
import "./Adminable.sol";
import "./IOPLimitOrder.sol";

contract OPLimitOrder is DelegateInterface, Adminable, ReentrancyGuard,
EIP712("OpenLeverage Limit Order", "1"), IOPLimitOrder, OPLimitOrderStorage
{

    using TransferHelper for IERC20;

    uint256 constant private MILLION = 10 ** 6;
    uint256 constant private QUINTILLION = 18;

    uint32 constant private TWAP = 60;

    uint256 constant private _ORDER_DOES_NOT_EXIST = 0;
    uint256 constant private _ORDER_FILLED = 1;

    /// @notice Stores unfilled amounts for each order plus one.
    /// Therefore 0 means order doesn't exist and 1 means order was filled
    mapping(bytes32 => uint256) private _remaining;

    function initialize(OpenLevInterface _openLev, DexAggregatorInterface _dexAgg) external {
        require(msg.sender == admin, "NAD");
        openLev = _openLev;
        dexAgg = _dexAgg;
    }


    function fillOpenOrder(OpenOrder memory order, bytes calldata signature, uint256 fillingDeposit, bytes memory dexData) external override nonReentrant {
        require(block.timestamp <= order.deadline, 'EXR');
        bytes32 orderId = _openOrderId(order);
        uint256 remainingDeposit = _remaining[orderId];
        require(remainingDeposit != _ORDER_FILLED, "RD0");
        if (remainingDeposit == _ORDER_DOES_NOT_EXIST) {
            remainingDeposit = order.deposit;
        } else {
            remainingDeposit -= 1;
        }
        require(fillingDeposit <= remainingDeposit, 'FTB');
        require(SignatureChecker.isValidSignatureNow(order.owner, _hashOpenOrder(order), signature), "SNE");

        uint256 fillingRatio = fillingDeposit * MILLION / order.deposit;
        require(fillingRatio > 0, 'FR0');

        OpenLevInterface.Market memory market = openLev.markets(order.marketId);
        // long token0 price lower than price0 or long token1 price higher than price0
        uint256 price = _getPrice(market.token0, market.token1, dexData);
        require((!order.longToken && price <= order.price0) || (order.longToken && price >= order.price0), 'PRE');

        address depositToken = order.depositToken ? market.token1 : market.token0;
        IERC20(depositToken).transferFrom(order.owner, address(this), fillingDeposit);
        IERC20(depositToken).safeApprove(address(openLev), fillingDeposit);
        //todo
        uint newHeld = _marginTrade(order, fillingRatio, dexData);
        require(newHeld * MILLION >= order.expectHeld * fillingRatio, 'NEG');

        uint commission = order.commission * fillingRatio / MILLION;
        if (commission > 0) {
            IERC20(order.commissionToken).transferFrom(order.owner, msg.sender, commission);
        }
        remainingDeposit = remainingDeposit - fillingDeposit;
        emit OrderFilled(msg.sender, orderId, commission, fillingDeposit, remainingDeposit);
        _remaining[orderId] = remainingDeposit + 1;
    }

    function fillCloseOrder(CloseOrder memory order, bytes calldata signature, uint256 fillingHeld, bytes memory dexData) external override nonReentrant {
        require(block.timestamp <= order.deadline, 'EXR');
        bytes32 orderId = _closeOrderId(order);
        uint256 remainingHeld = _remaining[orderId];
        require(remainingHeld != _ORDER_FILLED, "RD0");
        if (remainingHeld == _ORDER_DOES_NOT_EXIST) {
            remainingHeld = order.closeHeld;
        } else {
            remainingHeld -= 1;
        }
        require(fillingHeld <= remainingHeld, 'FTB');
        require(SignatureChecker.isValidSignatureNow(order.owner, _hashCloseOrder(order), signature), "SNE");

        uint256 fillingRatio = fillingHeld * MILLION / order.closeHeld;
        require(fillingRatio > 0, 'FR0');
        OpenLevInterface.Market memory market = openLev.markets(order.marketId);
        // stop profit
        if (!order.isStopLoss) {
            uint256 price = _getPrice(market.token0, market.token1, dexData);
            // long token0 price higher than price0 or long token1 price lower than price0
            require((!order.longToken && price >= order.price0) || (order.longToken && price <= order.price0), 'PRE');
        }
        // stop lose
        else {
            (uint256 price,uint256 cAvgPrice, uint256 hAvgPrice) = _getTwapPrice(market.token0, market.token1, dexData);
            require((!order.longToken && (price <= order.price0 && cAvgPrice <= order.price0 && hAvgPrice <= order.price0))
                || (order.longToken && (price >= order.price0 && cAvgPrice >= order.price0 && hAvgPrice >= order.price0)), 'UPF');
        }

        uint depositReturn = _closeTrade(order, fillingHeld, dexData);
        require(depositReturn * MILLION >= order.expectReturn * fillingRatio, 'NEG');

        uint commission = order.commission * fillingRatio / MILLION;
        if (commission > 0) {
            IERC20(order.commissionToken).transferFrom(order.owner, msg.sender, commission);
        }

        remainingHeld = remainingHeld - fillingHeld;
        emit OrderFilled(msg.sender, orderId, commission, fillingHeld, remainingHeld);
        _remaining[orderId] = remainingHeld + 1;
    }

    function closeTradeAndCancel(uint16 marketId, bool longToken, uint closeHeld, uint minOrMaxAmount, bytes memory dexData, OPLimitOrderStorage.Order[] memory orders) external override nonReentrant {
        openLev.closeTradeFor(msg.sender, marketId, longToken, closeHeld, minOrMaxAmount, dexData);
        for (uint i = 0; i < orders.length; i++) {
            _cancelOrder(orders[i]);
        }
    }

    function cancelOrder(Order memory order) external override {
        _cancelOrder(order);
    }

    function cancelOrders(Order[] memory orders) external override {
        for (uint i = 0; i < orders.length; i++) {
            _cancelOrder(orders[i]);
        }
    }

    function remaining(bytes32 _orderId) external override view returns (uint256){
        uint256 amount = _remaining[_orderId];
        require(amount != _ORDER_DOES_NOT_EXIST, "UKO");
        amount -= 1;
        return amount;
    }

    function remainingRaw(bytes32 _orderId) external override view returns (uint256){
        return _remaining[_orderId];
    }

    function orderId(Order memory order) external override view returns (bytes32) {
        return _orderId(order);
    }

    function hashOpenOrder(OPLimitOrderStorage.OpenOrder memory order) external override view returns (bytes32){
        return _hashOpenOrder(order);
    }

    function hashCloseOrder(OPLimitOrderStorage.CloseOrder memory order) external override view returns (bytes32){
        return _hashCloseOrder(order);
    }

    function _cancelOrder(Order memory order) internal {
        require(order.owner == msg.sender, "OON");
        bytes32 orderId = _orderId(order);
        uint256 orderRemaining = _remaining[orderId];
        require(orderRemaining != _ORDER_FILLED, "ALF");
        emit OrderCanceled(msg.sender, orderId, orderRemaining);
        _remaining[orderId] = _ORDER_FILLED;
    }


    function _marginTrade(OPLimitOrderStorage.OpenOrder memory order, uint256 fillingRatio, bytes memory dexData) internal returns (uint256){
        return openLev.marginTradeFor(order.owner, order.marketId, order.longToken, order.depositToken,
            order.deposit * fillingRatio / MILLION, order.borrow * fillingRatio / MILLION, 0, dexData);
    }

    function _closeTrade(OPLimitOrderStorage.CloseOrder memory order, uint256 fillingHeld, bytes memory dexData) internal returns (uint256){
        return openLev.closeTradeFor(order.owner, order.marketId, order.longToken, fillingHeld, order.longToken == order.depositToken ? type(uint256).max : 0, dexData);
    }

    function _getTwapPrice(address token0, address token1, bytes memory dexData) internal view returns (uint256 price, uint256 cAvgPrice, uint256 hAvgPrice){
        uint8 decimals;
        uint256 lastUpdateTime;
        (price, cAvgPrice, hAvgPrice, decimals, lastUpdateTime) = dexAgg.getPriceCAvgPriceHAvgPrice(token0, token1, TWAP, dexData);
        //ignore hAvgPrice
        if (block.timestamp >= lastUpdateTime + TWAP) {
            hAvgPrice = cAvgPrice;
        }
        if (decimals < QUINTILLION) {
            price = price * (10 ** (QUINTILLION - decimals));
            cAvgPrice = cAvgPrice * (10 ** (QUINTILLION - decimals));
            hAvgPrice = hAvgPrice * (10 ** (QUINTILLION - decimals));
        } else {
            price = price / (10 ** (decimals - QUINTILLION));
            cAvgPrice = cAvgPrice / (10 ** (decimals - QUINTILLION));
            hAvgPrice = hAvgPrice / (10 ** (decimals - QUINTILLION));
        }

    }

    function _getPrice(address token0, address token1, bytes memory dexData) internal view returns (uint256 price){
        uint8 decimals;
        (price, decimals) = dexAgg.getPrice(token0, token1, dexData);
        if (decimals < QUINTILLION) {
            price = price * (10 ** (QUINTILLION - decimals));
        } else {
            price = price / (10 ** (decimals - QUINTILLION));
        }

    }

    function _orderId(Order memory order) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    ORDER_TYPEHASH,
                    order
                )
            )
        );
    }

    function _openOrderId(OpenOrder memory openOrder) internal view returns (bytes32) {
        Order memory order;
        assembly {// solhint-disable-line no-inline-assembly
            order := openOrder
        }
        return _orderId(order);
    }

    function _closeOrderId(CloseOrder memory closeOrder) internal view returns (bytes32) {
        Order memory order;
        assembly {// solhint-disable-line no-inline-assembly
            order := closeOrder
        }
        return _orderId(order);
    }

    function _hashOpenOrder(OpenOrder memory order) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    OPEN_ORDER_TYPEHASH,
                    order
                )
            )
        );
    }

    function _hashCloseOrder(CloseOrder memory order) internal view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    CLOSE_ORDER_TYPEHASH,
                    order
                )
            )
        );
    }
}