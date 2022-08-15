const EIP712Domain = [
    {name: 'name', type: 'string'},
    {name: 'version', type: 'string'},
    {name: 'chainId', type: 'uint256'},
    {name: 'verifyingContract', type: 'address'},
];
/**
 *     struct Order {
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
 */
const Order = [
    {name: 'salt', type: 'uint256'},
    {name: 'owner', type: 'uint32'},
    {name: 'deadline', type: 'address'},
    {name: 'marketId', type: 'uint16'},
    {name: 'longToken', type: 'bool'},
    {name: 'depositToken', type: 'bool'},
    {name: 'commissionToken', type: 'address'},
    {name: 'commission', type: 'uint256'},
    {name: 'price0', type: 'uint256'}
];
/**
 *     struct OpenOrder {
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
 */
const OpenOrder = [
    {name: 'salt', type: 'uint256'},
    {name: 'owner', type: 'address'},
    {name: 'deadline', type: 'uint32'},
    {name: 'marketId', type: 'uint16'},
    {name: 'longToken', type: 'bool'},
    {name: 'depositToken', type: 'bool'},
    {name: 'commissionToken', type: 'address'},
    {name: 'commission', type: 'uint256'},
    {name: 'price0', type: 'uint256'},
    {name: 'deposit', type: 'uint256'},
    {name: 'borrow', type: 'uint256'},
    {name: 'expectHeld', type: 'uint256'}
];

/**
 *     struct CloseOrder {
        uint256 salt;
        address owner;
        uint32 deadline;
        uint16 marketId;
        bool longToken;
        bool depositToken;
        address commissionToken;
        uint256 commission;
        uint256 price0;// scale 10**18

        bool isStopLoss;
        uint256 closeHeld;
        uint256 expectReturn;
    }
 */
const CloseOrder = [
    {name: 'salt', type: 'uint256'},
    {name: 'owner', type: 'address'},
    {name: 'deadline', type: 'uint32'},
    {name: 'marketId', type: 'uint16'},
    {name: 'longToken', type: 'bool'},
    {name: 'depositToken', type: 'bool'},
    {name: 'commissionToken', type: 'address'},
    {name: 'commission', type: 'uint256'},
    {name: 'price0', type: 'uint256'},
    {name: 'isStopLoss', type: 'bool'},
    {name: 'closeHeld', type: 'uint256'},
    {name: 'expectReturn', type: 'uint256'}
];

const name = 'OpenLeverage Limit Order';
const version = '1';

function buildOrderData(chainId, verifyingContract, order) {
    return {
        primaryType: 'Order',
        types: {EIP712Domain, Order},
        domain: {name, version, chainId, verifyingContract},
        message: order,
    };
}

function buildOpenOrderData(chainId, verifyingContract, order) {
    return {
        primaryType: 'OpenOrder',
        types: {EIP712Domain, OpenOrder},
        domain: {name, version, chainId, verifyingContract},
        message: order,
    };
}

function buildCloseOrderData(chainId, verifyingContract, order) {
    return {
        primaryType: 'CloseOrder',
        types: {EIP712Domain, CloseOrder},
        domain: {name, version, chainId, verifyingContract},
        message: order,
    };
}


module.exports = {
    EIP712Domain,
    buildOrderData,
    buildOpenOrderData,
    buildCloseOrderData,
    name,
    version,
};
