const { expect } = require("chai");

describe("Margin contract", function () {
    let margin;
    let owner;
    let addr1;
    let liquidator;
    let addrs;
    let mockVAmm;
    let mockBaseToken;
    let vault;
    let ownerInitBaseAmount = 20000;
    let addr1InitBaseAmount = 100;
    let routerAllowance = 10000;
    let longSide = 0;
    let shortSide = 1;
    let config;

    beforeEach(async function () {
        [owner, addr1, liquidator, ...addrs] = await ethers.getSigners();

        const MockToken = await ethers.getContractFactory("MockToken");
        mockBaseToken = await MockToken.deploy("bit dao", "bit");
        mockQuoteToken = await MockToken.deploy("usdt dao", "usdt");

        const MockVAmm = await ethers.getContractFactory("MockVAmm");
        mockVAmm = await MockVAmm.deploy("amm shares", "as");

        const MockRouter = await ethers.getContractFactory("MockRouter");
        mockRouter = await MockRouter.deploy(mockBaseToken.address);

        const Vault = await ethers.getContractFactory("Vault");
        vault = await Vault.deploy(mockBaseToken.address, mockVAmm.address);

        const Config = await ethers.getContractFactory("Config");
        config = await Config.deploy();

        const Margin = await ethers.getContractFactory("Margin");
        margin = await Margin.deploy();

        await margin.initialize(
            mockBaseToken.address,
            mockQuoteToken.address,
            config.address,
            mockVAmm.address,
            vault.address
        )
        await mockRouter.setMarginContract(margin.address);
        await vault.setMargin(margin.address);

        await mockBaseToken.mint(owner.address, ownerInitBaseAmount);
        await mockBaseToken.mint(addr1.address, addr1InitBaseAmount);
        await mockBaseToken.approve(mockRouter.address, routerAllowance);
        await mockBaseToken.connect(addr1).approve(mockRouter.address, addr1InitBaseAmount);

        await config.setInitMarginRatio(909);
        await config.setLiquidateThreshold(10000);
        await config.setLiquidateFeeRatio(2000);
    });

    describe("add margin", function () {
        it("revert allowance when trader add margin from router", async function () {
            await expect(mockRouter.addMargin(addr1.address, routerAllowance + 1)).to.be.revertedWith(
                "ERC20: transfer amount exceeds allowance"
            );
        });

        it("add correct margin from router", async function () {
            await mockRouter.addMargin(addr1.address, routerAllowance);
            let position = await margin.traderPositionMap(addr1.address);
            expect(position[1]).to.equal(routerAllowance);
        });

        it("margin remain baseToken, trader add insufficient margin from margin", async function () {
            await mockBaseToken.connect(addr1).transfer(margin.address, addr1InitBaseAmount)
            await margin.addMargin(owner.address, addr1InitBaseAmount);
            let position = await margin.traderPositionMap(owner.address);
            expect(position[1]).to.equal(addr1InitBaseAmount);
        });

        it("add wrong margin", async function () {
            await expect(margin.addMargin(addr1.address, -10)).to.be.reverted;
            await expect(margin.addMargin(addr1.address, 0)).to.be.revertedWith(">0");
            await expect(margin.addMargin(addr1.address, 10)).to.be.revertedWith("wrong deposit amount");
        });


        describe("operate margin with old position", function () {
            beforeEach(async function () {
                let baseAmount = 10;

                await mockRouter.addMargin(owner.address, 1);
                await margin.openPosition(longSide, baseAmount);
                let position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-10);
                expect(position[1]).to.equal(11);
                expect(position[2]).to.equal(10);
            });

            it("add an old position", async function () {
                await mockRouter.addMargin(owner.address, 2);
                let position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-10);
                expect(position[1]).to.equal(13);
                expect(position[2]).to.equal(10);
            });
        })
    });

    describe("remove margin", async function () {
        beforeEach(async function () {
            await mockRouter.addMargin(owner.address, routerAllowance);
        });

        it("remove correct margin", async function () {
            await margin.removeMargin(routerAllowance);
            expect(await mockBaseToken.balanceOf(vault.address)).to.equal(0);
            expect(await mockBaseToken.balanceOf(owner.address)).to.equal(ownerInitBaseAmount);
        });

        it("no position, have baseToken, remove wrong margin", async function () {
            await expect(margin.removeMargin(0)).to.be.revertedWith(">0");
            await expect(margin.removeMargin(routerAllowance + 1)).to.be.revertedWith("preCheck withdrawable");
        });

        it("no position and no baseToken, remove margin", async function () {
            await margin.removeMargin(routerAllowance)
            await expect(margin.removeMargin(1)).to.be.revertedWith("preCheck withdrawable");
        });


        describe("operate margin with old position", function () {

            beforeEach(async function () {
                let baseAmount = 10;
                await margin.openPosition(longSide, baseAmount);
                let position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-10);
                expect(position[1]).to.equal(routerAllowance + 10);
                expect(position[2]).to.equal(10);

                await mockRouter.connect(addr1).addMargin(addr1.address, addr1InitBaseAmount);
                await margin.connect(addr1).openPosition(shortSide, baseAmount);
                position = await margin.traderPositionMap(addr1.address);
                expect(position[0]).to.equal(10);
                expect(position[1]).to.equal(addr1InitBaseAmount - 10);
                expect(position[2]).to.equal(10);
            });

            it("withdraw maximum margin from an old short position", async function () {
                await margin.connect(addr1).openPosition(shortSide, 5);
                position = await margin.traderPositionMap(addr1.address);
                expect(position[0]).to.equal(15);
                expect(position[1]).to.equal(85);
                expect(position[2]).to.equal(15);

                await expect(mockRouter.connect(addr1).removeMargin(addr1InitBaseAmount - 1)).to.be.revertedWith("preCheck withdrawable");
                await mockRouter.connect(addr1).removeMargin(addr1InitBaseAmount - 2)
                position = await margin.traderPositionMap(addr1.address);
                expect(position[0]).to.equal(15);
                expect(position[1]).to.equal(-13);
                expect(position[2]).to.equal(15);
            });

            it("withdraw maximum margin from an old short position", async function () {
                await mockRouter.connect(addr1).removeMargin(addr1InitBaseAmount - 1);
                position = await margin.traderPositionMap(addr1.address);
                expect(position[0]).to.equal(10);
                expect(position[1]).to.equal(-9);
                expect(position[2]).to.equal(10);
            });

            it("withdraw margin from an old position", async function () {
                await mockRouter.removeMargin(1);
                let position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-10);
                expect(position[1]).to.equal(routerAllowance + 10 - 1);
                expect(position[2]).to.equal(10);
            });

            it("withdraw maximum margin from an old long position", async function () {
                await mockRouter.removeMargin(routerAllowance - 1);
                let position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-10);
                expect(position[1]).to.equal(11);
                expect(position[2]).to.equal(10);
            });

            it("withdraw wrong margin from an old position", async function () {
                await expect(mockRouter.removeMargin(routerAllowance)).to.be.revertedWith("preCheck withdrawable");
            });
        })
    });

    describe("open position", async function () {
        beforeEach(async function () {
            await mockRouter.addMargin(owner.address, routerAllowance);
        });

        it("open correct long position", async function () {
            let baseAmount = 10;
            let price = 1;
            await margin.openPosition(longSide, baseAmount);
            position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.equal(0 - baseAmount * price);
            expect(position[1]).to.equal(routerAllowance + baseAmount);
        });

        it("open correct short position", async function () {
            let baseAmount = 10;
            let price = 1;
            await margin.openPosition(shortSide, baseAmount);
            position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.equal(baseAmount * price);
            expect(position[1]).to.equal(routerAllowance - baseAmount);
        });

        it("open wrong position", async function () {
            await expect(margin.openPosition(longSide, 0)).to.be.revertedWith(">0");
        });

        describe("open long first, then open long", async function () {
            beforeEach(async function () {
                let baseAmount = 10;
                await margin.removeMargin(routerAllowance - 1);
                await margin.openPosition(longSide, baseAmount);
                let position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-10);
                expect(position[1]).to.equal(11);
                expect(position[2]).to.equal(10);
            });

            it("old: quote -10, base 11; add long 5X position 1: quote -5, base +5; new: quote -15, base 17; add margin 1 first", async function () {
                await mockBaseToken.transfer(margin.address, 1)
                await margin.addMargin(owner.address, 1);

                let baseAmount = 5;
                await margin.openPosition(longSide, baseAmount);
                position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-15);
                expect(position[1]).to.equal(17);
                expect(position[2]).to.equal(15);
            });

            it("old: quote -10, base 11; add long 5X position 1: quote -5, base +5; new: quote -15, base 16; reverted", async function () {
                let baseAmount = 5;
                await expect(margin.openPosition(longSide, baseAmount)).to.be.reverted;
            });
        })

        describe("open short first, then open long", async function () {
            beforeEach(async function () {
                let baseAmount = 10;
                await margin.removeMargin(routerAllowance - 1);
                await margin.openPosition(shortSide, baseAmount);
                let position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(10);
                expect(position[1]).to.equal(-9);
                expect(position[2]).to.equal(10);
            });

            it("old: quote 10, base -9; add long 5X position: quote -5, base +5; new: quote 5, base -4", async function () {
                let baseAmount = 5;
                await margin.openPosition(longSide, baseAmount);
                position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(5);
                expect(position[1]).to.equal(-4);
                expect(position[2]).to.equal(5);
            });

            it("old: quote 10, base -9; add long 15X position: quote -15, base +15; new: quote -5, base 6", async function () {
                let baseAmount = 15;
                await margin.openPosition(longSide, baseAmount);
                position = await margin.traderPositionMap(owner.address);
                expect(position[0]).to.equal(-5);
                expect(position[1]).to.equal(6);
                expect(position[2]).to.equal(5);
            });

            it("old: quote 10, base -9; add long 21X position 1: quote -21, base +21; new: quote -11, base 12; reverted", async function () {
                let baseAmount = 21;
                await expect(margin.openPosition(longSide, baseAmount)).to.be.reverted;
            });
        })

    });

    describe("close position", async function () {
        beforeEach(async function () {
            await mockRouter.addMargin(owner.address, routerAllowance);
            let baseAmount = 10;
            let price = 1;
            await margin.openPosition(longSide, baseAmount);
            position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.equal(0 - baseAmount * price);
            expect(position[1]).to.equal(routerAllowance + baseAmount);
        });

        it("close all position", async function () {
            let position = await margin.traderPositionMap(owner.address);
            await margin.closePosition(position.quoteSize.abs());
            position = await margin.traderPositionMap(owner.address);

            expect(position[0]).to.equal(0);
        });

        it("close position partly", async function () {
            let position = await margin.traderPositionMap(owner.address);
            await margin.closePosition(position.quoteSize.abs() - 1);
            position = await margin.traderPositionMap(owner.address);

            expect(position[0]).to.equal(-1);
        });

        it("close Null position, reverted", async function () {
            let position = await margin.traderPositionMap(owner.address);
            await margin.closePosition(position.quoteSize.abs());

            await expect(margin.closePosition(10)).to.be.revertedWith("position cant 0")
        });

        it("close wrong position, reverted", async function () {
            let position = await margin.traderPositionMap(owner.address);
            await expect(margin.closePosition(0)).to.be.revertedWith("position cant 0");
            await expect(margin.closePosition(position.quoteSize.abs() + 1)).to.be.revertedWith("above position");
        });
    });

    describe("liquidate", async function () {
        beforeEach(async function () {
            await mockRouter.connect(addr1).addMargin(addr1.address, addr1InitBaseAmount);
            await mockRouter.addMargin(owner.address, 8);
            let baseAmount = 10;
            await margin.connect(addr1).openPosition(longSide, baseAmount);
        });

        it("liquidate 0 position, reverted", async function () {
            await expect(margin.connect(liquidator).liquidate(owner.address)).to.be.revertedWith("position 0");
        })

        it("liquidate normal position, reverted", async function () {
            await expect(margin.connect(liquidator).liquidate(addr1.address)).to.be.revertedWith("not liquidatable");
        })

        it("liquidate liquidatable position", async function () {
            let baseAmount = 10;
            await margin.connect(addr1).openPosition(longSide, baseAmount);
            await margin.connect(liquidator).liquidate(addr1.address);
            let position = await margin.traderPositionMap(addr1.address);
            expect(position[0]).to.equal(0);
            expect(position[1]).to.equal(0);
            expect(position[2]).to.equal(0);
            expect((await mockBaseToken.balanceOf(liquidator.address)).toNumber()).to.greaterThan(0)
        })

    });
    describe("get margin ratio", async function () {
        beforeEach(async function () {
            await mockRouter.addMargin(owner.address, 1);
            let baseAmount = 10;
            await margin.openPosition(longSide, baseAmount);

            await mockRouter.addMargin(addr1.address, 1);
            await margin.connect(addr1).openPosition(shortSide, baseAmount);
        });

        it("quote -10, base 11; 1/11, margin ratio is 9.09%", async function () {
            expect(await margin.getMarginRatio(owner.address)).to.equal(910)
        });

        it("quote -10, base 12; 2/12, margin ratio is 16.66%", async function () {
            await mockRouter.addMargin(owner.address, 1);
            expect(await margin.getMarginRatio(owner.address)).to.equal(1667)
        });

        it("quote 10, base -9; 1/10, margin ratio is 10.00%", async function () {
            expect(await margin.getMarginRatio(addr1.address)).to.equal(1000)
        });

        it("quote 10, base -8; 2/10, margin ratio is 20.00%", async function () {
            await mockRouter.addMargin(addr1.address, 1);
            expect(await margin.getMarginRatio(addr1.address)).to.equal(2000)
        });
    });



    describe("get withdrawable margin", async function () {
        beforeEach(async function () {
            await mockRouter.addMargin(owner.address, 1);
            let baseAmount = 10;
            await margin.openPosition(longSide, baseAmount);

            await mockRouter.addMargin(addr1.address, 1);
            await margin.connect(addr1).openPosition(shortSide, baseAmount);
        });

        it("quote -10, base 11; withdrawable is 0", async function () {
            expect(await margin.getWithdrawable(owner.address)).to.equal(0)
        });

        it("quote -10, base 12; withdrawable is 1", async function () {
            await mockRouter.addMargin(owner.address, 1);
            expect(await margin.getWithdrawable(owner.address)).to.equal(1)
        });

        it("quote 10, base -9; withdrawable is 0", async function () {
            expect(await margin.getWithdrawable(addr1.address)).to.equal(0)
        });

        it("quote 10, base -8; withdrawable is 1", async function () {
            await mockRouter.addMargin(addr1.address, 1);
            expect(await margin.getWithdrawable(addr1.address)).to.equal(1)
        });
    });


});
