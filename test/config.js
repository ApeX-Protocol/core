const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("Config contract", function () {
    let config;
    beforeEach(async function () {
        [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();

        const Config = await ethers.getContractFactory("Config");
        config = await Config.deploy(10, 100, 20);

    });
    describe("set initMarginRatio", async function () {
        it("set correct ratio", async function () {
            await config.setInitMarginRatio(10);
            expect(await config.initMarginRatio()).to.equal(10);
        });

        it("set wrong ratio, reverted", async function () {
            await expect(config.setInitMarginRatio(9)).to.be.revertedWith("ratio >= 10");
        });

        it("addr1 set, reverted", async function () {
            await expect(config.connect(addr1).setInitMarginRatio(9)).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });

    describe("set liquidateThreshold", async function () {
        it("set correct threshold", async function () {
            await config.setLiquidateThreshold(100);
            expect(await config.liquidateThreshold()).to.equal(100);
        });

        it("set wrong threshold", async function () {
            await expect(config.setLiquidateThreshold(80)).to.be.revertedWith("90 < liquidateThreshold <= 100");
        });
    });

    describe("set liquidateFeeRatio", async function () {
        it("set correct fee ratio", async function () {
            await config.setLiquidateFeeRatio(10);
            expect(await config.liquidateFeeRatio()).to.equal(10);
        });

        it("set wrong fee ratio", async function () {
            await expect(config.setLiquidateFeeRatio(20)).to.be.revertedWith("0 < liquidateFeeRatio <= 10");
        });
    });
});
