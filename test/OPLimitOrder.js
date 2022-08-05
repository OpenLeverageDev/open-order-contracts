const OPLimitOrder = artifacts.require("OPLimitOrder");
const OPLimitOrderDelegator = artifacts.require("OPLimitOrderDelegator");
const MockToken = artifacts.require("MockToken");
const MockOpenLev = artifacts.require("MockOpenLev");
const MockDexAgg = artifacts.require("MockDexAgg");

const {expectRevert} = require('@openzeppelin/test-helpers');
const {bufferToHex, zeroAddress} = require('ethereumjs-util');
const ethSigUtil = require('eth-sig-util');
const m = require('mocha-logger');
const {buildOpenOrderData, buildCloseOrderData} = require("./util/orderUtils");
const {TypedDataUtils} = require("eth-sig-util");

contract("OPLimitOrder", async accounts => {
    let limitOrder;
    let token0;
    let token1;
    let commissionToken;
    let openLev;
    let dexAgg;
    let admin = accounts[0];
    let trader = accounts[1];
    let bot = accounts[2];
    const privatekey = Buffer.from('a06e28a7c518d240d543c815b598324445bceb6c4bcd06c99d54ad2794df2925', 'hex');

    let initSupply = toWei(1000000000);
    let chainId;
    let dexData = '0x01';
    let ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

    async function initMarginTrade(longToken, depositToken, held) {
        await token0.mint(admin, held);
        await token0.approve(openLev.address, held, {from: admin});
        await openLev.setNewHeld(held);
        await openLev.marginTradeFor(trader, 0, longToken, depositToken, held, 1, 0, dexData);
    }

    function buildOpenOrder(
        deposit = 1,
        expectHeld = 3,
        deadline = 4294967295,
        borrow = 2,
        price0 = 0,
        commission = 1,
        longToken = false
    ) {
        return buildOpenOrderWithSalt("1", deposit, expectHeld, deadline, borrow, price0, commission, longToken);
    }

    function buildOpenOrderWithSalt(
        salt,
        deposit = 1,
        expectHeld = 3,
        deadline = 4294967295,
        borrow = 2,
        price0 = 0,
        commission = 1,
        longToken = false
    ) {
        return {
            salt: salt,
            owner: trader,
            deadline: deadline,
            marketId: 0,
            longToken: longToken,
            depositToken: false,
            commissionToken: commissionToken.address,
            commission: commission,
            price0: price0,
            deposit: deposit,
            borrow: borrow,
            expectHeld: expectHeld
        }
    }

    function buildCloseOrder(closeHeld = 1,
                             expectReturn = 1,
                             price0 = 0,
                             isStopLose = false,
                             deadline = 4294967295,
                             longToken = false,
                             commission = 1) {
        return buildCloseOrderWithSalt("1", closeHeld, expectReturn, price0, isStopLose, deadline, longToken, commission);
    }

    function buildCloseOrderWithSalt(salt,
                                     closeHeld = 1,
                                     expectReturn = 1,
                                     price0 = 0,
                                     isStopLose = false,
                                     deadline = 4294967295,
                                     longToken = false,
                                     commission = 1) {
        return {
            salt: salt,
            owner: trader,
            deadline: deadline,
            marketId: 0,
            longToken: longToken,
            depositToken: false,
            commissionToken: commissionToken.address,
            commission: commission,
            price0: price0,
            isStopLose: isStopLose,
            closeHeld: closeHeld,
            expectReturn: expectReturn
        }
    }

    function openOrder2Order(openOrder) {
        let order = Object.assign({}, openOrder);
        delete order.deposit;
        delete order.borrow;
        delete order.expectHeld;
        return order;
    }

    function closeOrder2Order(closeOrder) {
        let order = Object.assign({}, closeOrder);
        delete order.isStopLose;
        delete order.closeHeld;
        delete order.expectReturn;
        return order;
    }

    beforeEach(async () => {
        token0 = await MockToken.new("Token0", "TK0", initSupply, {from: admin});
        commissionToken = token0;
        token1 = await MockToken.new("Token1", "TK1", initSupply, {from: admin});
        chainId = await token0.getChainId();
        dexAgg = await MockDexAgg.new();
        openLev = await MockOpenLev.new(dexAgg.address);
        await openLev.createMarket(token0.address, token1.address);
        await token0.mint(openLev.address, initSupply);
        await token1.mint(openLev.address, initSupply);
        let limitOrderImpl = await OPLimitOrder.new();
        limitOrder = await OPLimitOrderDelegator.new(openLev.address, dexAgg.address, admin, limitOrderImpl.address);
        limitOrder = await OPLimitOrder.at(limitOrder.address);
        await token0.approve(limitOrder.address, initSupply, {from: trader});
        await token1.approve(limitOrder.address, initSupply, {from: trader});
    });

    it("create and fill open order", async () => {
        let deposit = 1;
        let expectHeld = 3;
        await token0.mint(trader, 2);
        const order = buildOpenOrder(deposit, expectHeld);
        const data = buildOpenOrderData(chainId, limitOrder.address, order);
        let hash = TypedDataUtils.sign(data).toString('hex');
        expect('0x' + hash).equal(await limitOrder.hashOpenOrder(order));
        const signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await openLev.setNewHeld(expectHeld);
        let tx = await limitOrder.fillOpenOrder(order, signature, deposit, dexData, {from: bot});
        m.log("Fill open order gas used =", tx.receipt.gasUsed);
        let trade = await openLev.activeTrades(trader, 0, false);
        expect(trade.deposited).equal('1');
        expect(trade.held).equal('3');
        expect(trade.depositToken).equal(false);
        expect((await commissionToken.balanceOf(bot)).toString()).equal('1');
        expect((await token0.balanceOf(trader)).toString()).equal('0');
    })

    it("create and fill stop profit order", async () => {
        let closeHeld = 1;
        let expectReturn = 1;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn);
        const data = buildCloseOrderData(chainId, limitOrder.address, order);
        let hash = TypedDataUtils.sign(data).toString('hex');
        expect('0x' + hash).equal(await limitOrder.hashCloseOrder(order));
        const signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await openLev.setDepositReturn(expectReturn);
        let tx = await limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot});
        m.log("Fill close order gas used =", tx.receipt.gasUsed);
        expect((await commissionToken.balanceOf(bot)).toString()).equal('1');
        expect((await token0.balanceOf(trader)).toString()).equal('1');
    })

    it("create and fill stop loss order", async () => {
        let closeHeld = 1;
        let expectReturn = 1;
        let stopLosePrice0 = 2;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn, stopLosePrice0, true);
        const data = buildCloseOrderData(chainId, limitOrder.address, order);
        const signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await openLev.setDepositReturn(expectReturn);
        await dexAgg.setPrice(1, 1, 1, 0);
        await limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot});
        expect((await commissionToken.balanceOf(bot)).toString()).equal('1');
        expect((await token0.balanceOf(trader)).toString()).equal('1');
    })

    it("create and cancel open order", async () => {
        const openOrder = buildOpenOrder();
        const order = openOrder2Order(openOrder);
        let tx = await limitOrder.cancelOrder(order, {from: trader});
        m.log("Cancel open order gas used =", tx.receipt.gasUsed);
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(order))).toString()).equal('1');
    })

    it("create and cancel close order", async () => {
        const closeOrder = buildCloseOrder();
        const order = closeOrder2Order(closeOrder);
        let tx = await limitOrder.cancelOrder(order, {from: trader});
        m.log("Cancel close order gas used =", tx.receipt.gasUsed);
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(order))).toString()).equal('1');
    })

    it("cancel orders batch", async () => {
        const openOrder1 = buildOpenOrderWithSalt("1");
        const openOrder2 = buildOpenOrderWithSalt("2");
        const closeOrder1 = buildCloseOrderWithSalt("3");
        const closeOrder2 = buildCloseOrderWithSalt("4");
        let orders = [openOrder2Order(openOrder1), openOrder2Order(openOrder2), closeOrder2Order(closeOrder1), closeOrder2Order(closeOrder2)];
        let tx = await limitOrder.cancelOrders(orders, {from: trader});
        m.log("Cancel 4 orders gas used =", tx.receipt.gasUsed);
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(openOrder2Order(openOrder1)))).toString()).equal('1');
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(openOrder2Order(openOrder2)))).toString()).equal('1');
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(closeOrder2Order(closeOrder1)))).toString()).equal('1');
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(closeOrder2Order(closeOrder2)))).toString()).equal('1');
    })

    it("fill open order in 'EXR' error case", async () => {
        let deposit = 1;
        const order = buildOpenOrder(deposit, 3, 1);
        const data = buildOpenOrderData(chainId, limitOrder.address, order);
        const signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, deposit, dexData, {from: bot}),
            'EXR',
        );
    })

    it("fill open order in 'RD0' error case", async () => {
        let deposit = 1;
        let expectHeld = 3;
        await token0.mint(trader, 2);
        const order = buildOpenOrder(deposit, expectHeld);
        let data = buildOpenOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await openLev.setNewHeld(expectHeld);
        await limitOrder.fillOpenOrder(order, signature, deposit, dexData, {from: bot});
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, deposit, dexData, {from: bot}),
            'RD0',
        );

        const openOrder2 = buildOpenOrderWithSalt("2");
        data = buildOpenOrderData(chainId, limitOrder.address, openOrder2);
        signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await limitOrder.cancelOrder(openOrder2, {from: trader});
        await expectRevert(
            limitOrder.fillOpenOrder(openOrder2, signature, deposit, dexData, {from: bot}),
            'RD0',
        );

    })

    it("fill open order in 'FTB' error case", async () => {
        let deposit = 2;
        let expectHeld = 3;
        await token0.mint(trader, 2);
        const order = buildOpenOrder(deposit, expectHeld);
        let data = buildOpenOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await openLev.setNewHeld(expectHeld);
        await limitOrder.fillOpenOrder(order, signature, deposit - 1, dexData, {from: bot});
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, deposit, dexData, {from: bot}),
            'FTB',
        );
    })

    it("fill open order in 'SNE' error case", async () => {
        let deposit = 2;
        let expectHeld = 3;
        const order = buildOpenOrder(deposit, expectHeld);
        order.expectHeld = 4;
        let data = buildOpenOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data});
        order.expectHeld = 3;
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, deposit, dexData, {from: bot}),
            'SNE',
        );
    })

    it("fill open order in 'FR0' error case", async () => {
        let deposit = 2;
        const order = buildOpenOrder(deposit);
        let data = buildOpenOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, 0, dexData, {from: bot}),
            'FR0',
        );
    })

    it("fill open order in 'PRE' error case", async () => {
        let deposit = 2;
        await token0.mint(trader, 2);
        let order = buildOpenOrder(deposit, 3, 4294967295, 2, 1);
        let data = buildOpenOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await dexAgg.setPrice(3, 1, 1, 0);
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, 1, dexData, {from: bot}),
            'PRE',
        );
        await token0.mint(trader, 2);
        order = buildOpenOrder(deposit, 3, 4294967295, 2, 2, 0, true);
        data = buildOpenOrderData(chainId, limitOrder.address, order);
        signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await dexAgg.setPrice(1, 1, 1, 0);
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, 1, dexData, {from: bot}),
            'PRE',
        );
    })

    it("fill open order in 'NEG' error case", async () => {
        let deposit = 2;
        let expectHeld = 3;
        await token0.mint(trader, 2);
        const order = buildOpenOrder(deposit, expectHeld);
        let data = buildOpenOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await openLev.setNewHeld(1);
        // must gt 1.5
        await expectRevert(
            limitOrder.fillOpenOrder(order, signature, deposit - 1, dexData, {from: bot}),
            'NEG',
        );
    })

    it("fill close order in 'EXR' error case", async () => {
        let closeHeld = 1;
        let expectReturn = 1;
        const order = buildCloseOrder(closeHeld, expectReturn, 0, 1, 1);
        const data = buildCloseOrderData(chainId, limitOrder.address, order);
        const signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'EXR',
        );
    })

    it("fill close order in 'RD0' error case", async () => {
        let closeHeld = 1;
        let expectReturn = 1;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn);
        let data = buildCloseOrderData(chainId, limitOrder.address, order);

        let signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await openLev.setDepositReturn(expectReturn);
        await limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot});

        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'RD0',
        );

        const closeOrder2 = buildCloseOrderWithSalt("2");
        data = buildCloseOrderData(chainId, limitOrder.address, closeOrder2);
        signature = ethSigUtil.signTypedMessage(privatekey, {data});
        await limitOrder.cancelOrder(closeOrder2, {from: trader});
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'RD0',
        );

    })

    it("fill close order in 'FTB' error case", async () => {
        let closeHeld = 2;
        let expectReturn = 2;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn);
        let data = buildCloseOrderData(chainId, limitOrder.address, order);

        let signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await openLev.setDepositReturn(expectReturn);
        await limitOrder.fillCloseOrder(order, signature, closeHeld - 1, dexData, {from: bot});
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'FTB',
        );
    })

    it("fill close order in 'SNE' error case", async () => {
        let closeHeld = 2;
        let expectReturn = 2;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn);
        order.expectReturn = 3;
        let data = buildCloseOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        order.expectReturn = 2;
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'SNE',
        );
    })

    it("fill close order in 'FR0' error case", async () => {
        let closeHeld = 2;
        let expectReturn = 2;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn);
        let data = buildCloseOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, 0, dexData, {from: bot}),
            'FR0',
        );
    })

    it("fill close order in 'PRE' error case", async () => {
        let closeHeld = 2;
        let expectReturn = 2;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        let order = buildCloseOrder(closeHeld, expectReturn, 2);
        let data = buildCloseOrderData(chainId, limitOrder.address, order);
        let signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await dexAgg.setPrice(1, 1, 1, 0);
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'PRE',
        );
        await initMarginTrade(true, false, closeHeld);
        await token0.mint(trader, 1);
        order = buildCloseOrder(closeHeld, expectReturn, 2, false, 4294967295, true);
        data = buildCloseOrderData(chainId, limitOrder.address, order);
        signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        dexAgg.setPrice(3, 1, 1, 0);
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'PRE',
        );
    })

    it("fill close order in 'UPF' error case", async () => {
        let closeHeld = 1;
        let expectReturn = 1;
        let stopLosePrice0 = 2;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn, stopLosePrice0, true);
        const data = buildCloseOrderData(chainId, limitOrder.address, order);
        const signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await openLev.setDepositReturn(expectReturn);
        await dexAgg.setPrice(3, 1, 1, 0);
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'UPF',
        );
        await dexAgg.setPrice(1, 3, 1, 0);
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'UPF',
        );
        await dexAgg.setPrice(1, 1, 3, await timestamp(0));
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'UPF',
        );

        await dexAgg.setPrice(1, 1, 3, await timestamp(-1));
        await limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot});
    })

    it("fill close order in 'NEG' error case", async () => {
        let closeHeld = 2;
        let expectReturn = 2;
        await initMarginTrade(false, false, closeHeld);
        await token0.mint(trader, 1);
        const order = buildCloseOrder(closeHeld, expectReturn);
        let data = buildCloseOrderData(chainId, limitOrder.address, order);

        let signature = ethSigUtil.signTypedMessage(privatekey, {data: data});
        await openLev.setDepositReturn(expectReturn - 1);
        await expectRevert(
            limitOrder.fillCloseOrder(order, signature, closeHeld, dexData, {from: bot}),
            'NEG',
        );
    })

    it("close trade and cancel orders", async () => {
        let closeHeld = 2;
        let expectReturn = 2;
        await initMarginTrade(false, false, closeHeld);
        const closeOrder1 = buildCloseOrderWithSalt("3");
        const closeOrder2 = buildCloseOrderWithSalt("4");
        let orders = [closeOrder2Order(closeOrder1), closeOrder2Order(closeOrder2)];
        await openLev.setDepositReturn(expectReturn);
        await limitOrder.closeTradeAndCancel(0, false, closeHeld, 0, '0x', orders, {from: trader});
        expect((await token0.balanceOf(trader)).toString()).equal('2');
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(closeOrder2Order(closeOrder1)))).toString()).equal('1');
        expect((await limitOrder.remainingRaw(await limitOrder.orderId(closeOrder2Order(closeOrder2)))).toString()).equal('1');
    })

    it("initialize in 'NAD' error case", async () => {
        await expectRevert(
            limitOrder.initialize(ZERO_ADDRESS, ZERO_ADDRESS, {from: bot}),
            'NAD',
        );
    })

    async function timestamp(plusMins) {
        let lastbk = await web3.eth.getBlock('latest');
        return lastbk.timestamp + plusMins * 60;
    }

    function toWei(eth) {
        return web3.utils.toWei(toBN(eth), 'ether')
    }

    function toBN(s) {
        return web3.utils.toBN(s);
    }
})
