const OpenOrder = artifacts.require("OpenOrder");

contract("OpenOrders", async accounts => {

    it("should create order properly", async () => {})

    it("should execute margin trade properly", async () => {})

    it("should execute limit close order properly", async () => {})

    it("should execute limit stop loss order properly", async () => {})

    it("should execute margin trade by sig properly", async () => {})

    it("should execute limit close order by sig properly", async () => {})

    it("should execute limit stop loss order by sig  properly", async () => {})

    it("should failed when executing limit stop loss order under flash loan attack", async () => {})

    it("should failed when executing order with wrong sig", async () => {})

    it("should failed when executing order with used sig", async () => {})

    it("should failed when executing order with wrong nonce", async () => {})

    it("should failed when target is contract", async() => {})

    it("should work proerply on taxToken", async() => {})

})
