const { expect } = require("chai");

describe("PCVTreasury contract", function () {
    let owner;
    let other;
    let bondPool;
    let policy;
    let slpToken;
    let apeXToken;
    let pcvTreasury;

    beforeEach(async function () {
        [owner, other, bondPool] = await ethers.getSigners();
        
        const MockToken = await ethers.getContractFactory("MockToken");
        apeXToken = await MockToken.deploy("ApeX Token", "APEX");
        slpToken = await MockToken.deploy("slp token", "SLP");
        
        const PCVTreasury = await ethers.getContractFactory("PCVTreasury");
        pcvTreasury = await PCVTreasury.deploy(apeXToken.address);

        const MockPCVPolicy = await ethers.getContractFactory("MockPCVPolicy");
        policy = await MockPCVPolicy.deploy();
    });

    describe("addLiquidityToken", function () {
        it("add a new lpToken", async function () {
            await pcvTreasury.addLiquidityToken(slpToken.address);
            expect(await pcvTreasury.isLiquidityToken(slpToken.address)).to.equal(true);
        });

        it("add a lpToken already added", async function () {
            await pcvTreasury.addLiquidityToken(slpToken.address);
            await expect(pcvTreasury.addLiquidityToken(slpToken.address)).to.be.revertedWith("PCVTreasury.addLiquidityToken: ALREADY_ADDED");
        });

        it("not admin add a lpToken", async function () {
            let pcvTreasuryAsOther = pcvTreasury.connect(other);
            await expect(pcvTreasuryAsOther.addLiquidityToken(slpToken.address)).to.be.revertedWith("Ownable: REQUIRE_OWNER");
        });
    });

    describe("addBondPool", function () {
        it("add a new bondPool", async function () {
            await pcvTreasury.addBondPool(bondPool.address);
            expect(await pcvTreasury.isBondPool(bondPool.address)).to.equal(true);
        });

        it("add a bondPool already added", async function () {
            await pcvTreasury.addBondPool(bondPool.address);
            await expect(pcvTreasury.addBondPool(bondPool.address)).to.be.revertedWith("PCVTreasury.addBondPool: ALREADY_ADDED");
        });

        it("not admin add a bondPool", async function () {
            let pcvTreasuryAsOther = pcvTreasury.connect(other);
            await expect(pcvTreasuryAsOther.addBondPool(bondPool.address)).to.be.revertedWith("Ownable: REQUIRE_OWNER");
        });
    });

    describe("deposit", function () {
        it("deposit with unsupported bondPool", async function () {
            await apeXToken.mint(pcvTreasury.address, 3000);
            await slpToken.mint(bondPool.address, 2000);

            let slpTokenAsBondPool = slpToken.connect(bondPool);
            await slpTokenAsBondPool.approve(pcvTreasury.address, 1000);
            
            let pcvTreasuryAsBondPool = pcvTreasury.connect(bondPool);
            await expect(pcvTreasuryAsBondPool.deposit(slpToken.address, 1000, 1000)).to.be.revertedWith("PCVTreasury.deposit: FORBIDDEN");
        });

        it("deposit with unsupported lpToken", async function () {
            await pcvTreasury.addBondPool(bondPool.address);

            await apeXToken.mint(pcvTreasury.address, 3000);
            await slpToken.mint(bondPool.address, 2000);

            let slpTokenAsBondPool = slpToken.connect(bondPool);
            await slpTokenAsBondPool.approve(pcvTreasury.address, 1000);
            
            let pcvTreasuryAsBondPool = pcvTreasury.connect(bondPool);
            await expect(pcvTreasuryAsBondPool.deposit(slpToken.address, 1000, 1000)).to.be.revertedWith("PCVTreasury.deposit: NOT_LIQUIDITY_TOKEN");
        });

        it("deposit with not approved", async function () {
            await pcvTreasury.addBondPool(bondPool.address);
            await pcvTreasury.addLiquidityToken(slpToken.address);

            await apeXToken.mint(pcvTreasury.address, 3000);
            await slpToken.mint(bondPool.address, 2000);

            let slpTokenAsBondPool = slpToken.connect(bondPool);
            // await slpTokenAsBondPool.approve(pcvTreasury.address, 1000);
            
            let pcvTreasuryAsBondPool = pcvTreasury.connect(bondPool);
            await expect(pcvTreasuryAsBondPool.deposit(slpToken.address, 1000, 1000)).to.be.revertedWith("TransferHelper::transferFrom: transferFrom failed");
        });

        it("deposit with not enough apeX", async function () {
            await pcvTreasury.addBondPool(bondPool.address);
            await pcvTreasury.addLiquidityToken(slpToken.address);

            // await apeXToken.mint(pcvTreasury.address, 3000);
            await slpToken.mint(bondPool.address, 2000);

            let slpTokenAsBondPool = slpToken.connect(bondPool);
            await slpTokenAsBondPool.approve(pcvTreasury.address, 1000);
            
            let pcvTreasuryAsBondPool = pcvTreasury.connect(bondPool);
            await expect(pcvTreasuryAsBondPool.deposit(slpToken.address, 1000, 1000)).to.be.revertedWith("PCVTreasury.deposit: NOT_ENOUGH_APEX");
        });

        it("deposit success", async function () {
            await pcvTreasury.addBondPool(bondPool.address);
            await pcvTreasury.addLiquidityToken(slpToken.address);

            await apeXToken.mint(pcvTreasury.address, 3000);
            await slpToken.mint(bondPool.address, 2000);

            let slpTokenAsBondPool = slpToken.connect(bondPool);
            await slpTokenAsBondPool.approve(pcvTreasury.address, 1000);

            let pcvTreasuryAsBondPool = pcvTreasury.connect(bondPool);
            await pcvTreasuryAsBondPool.deposit(slpToken.address, 1000, 1000);

            let slpLeft = await slpToken.balanceOf(bondPool.address);
            let slpInTreasury = await slpToken.balanceOf(pcvTreasury.address);
            let apeXLeft = await apeXToken.balanceOf(pcvTreasury.address);
            let apeXInBondPool = await apeXToken.balanceOf(bondPool.address);

            console.log("slpLeft:", slpLeft.toNumber());
            console.log("slpInTreasury:", slpInTreasury.toNumber());
            console.log("apeXLeft:", apeXLeft.toNumber());
            console.log("apeXInBondPool:", apeXInBondPool.toNumber());
            
            expect(slpLeft.toNumber()).to.equal(1000);
            expect(slpInTreasury.toNumber()).to.equal(1000);
            expect(apeXLeft.toNumber()).to.equal(2000);
            expect(apeXInBondPool.toNumber()).to.equal(1000);
        });
    });

    describe("withdraw", function () {
        it("admin withdraw", async function () {
            await pcvTreasury.addLiquidityToken(slpToken.address);
            await slpToken.mint(pcvTreasury.address, 2000);
            await pcvTreasury.withdraw(slpToken.address, policy.address, 1000, 0x0);
            let slpLeft = await slpToken.balanceOf(pcvTreasury.address);
            let slpInPolicy = await slpToken.balanceOf(policy.address);
            expect(slpLeft.toNumber()).to.equal(1000);
            expect(slpInPolicy.toNumber()).to.equal(1000);
        });

        it("other withdraw", async function () {
            await pcvTreasury.addLiquidityToken(slpToken.address);
            await slpToken.mint(pcvTreasury.address, 2000);
            let pcvTreasuryAsOther = pcvTreasury.connect(other);
            await expect(pcvTreasuryAsOther.withdraw(slpToken.address, policy.address, 1000, 0x0)).to.be.revertedWith("Ownable: REQUIRE_OWNER");
        });
    });

    describe("grantApeX", function () {
        it("other grantApeX", async function () {
            await pcvTreasury.addLiquidityToken(slpToken.address);
            await slpToken.mint(pcvTreasury.address, 2000);
            let pcvTreasuryAsOther = pcvTreasury.connect(other);
            await expect(pcvTreasuryAsOther.grantApeX(owner.address, 1000)).to.be.revertedWith("Ownable: REQUIRE_OWNER");
        });

        it("admin grantApeX", async function () {
            await pcvTreasury.addLiquidityToken(slpToken.address);
            await apeXToken.mint(pcvTreasury.address, 3000);
            await pcvTreasury.grantApeX(other.address, 1000);
            let left = await apeXToken.balanceOf(pcvTreasury.address);
            let granted = await apeXToken.balanceOf(other.address);
            expect(left.toNumber()).to.equal(2000);
            expect(granted.toNumber()).to.equal(1000);
        });
    });
});