const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("Library contract", function () {
    let testLibrary;
    let uintMaxHex = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
    let uintMax = BigNumber.from(uintMaxHex)

    beforeEach(async function () {
        const TestLibrary = await ethers.getContractFactory("TestLibrary");
        testLibrary = await TestLibrary.deploy();
    });


    describe("math.sol", function () {

        it("min(1,2) is 1", async function () {
            expect(await testLibrary.mathMin(1, 2)).to.equal(1)
        });

        it("min(-1,2) is -1", async function () {
            expect(await testLibrary.mathMin(-1, 2)).to.equal(-1)
        });

        it("minU(1,2) is 1", async function () {
            expect(await testLibrary.mathMinU(1, 2)).to.equal(1)
        });

        it("minU(1,uintMax) is 1", async function () {
            expect(await testLibrary.mathMinU(1, uintMax)).to.equal(1)
        });
    })

    describe("decimal.sol", function () {

        it("decimalSub(2,1) is 1", async function () {
            expect(await testLibrary.decimalSub(2, 1)).to.equal(1)
        });

        it("fail decimalSub(1,2)", async function () {
            let e;
            try {
                await testLibrary.decimalSub(1, 2)
            } catch (error) {
                e = error
            }

            expect(e).to.not.equal(undefined)
        });

        it("decimalAdd(2,1) is 3", async function () {
            expect(await testLibrary.decimalAdd(2, 1)).to.equal(3)
        });


        it("fail decimalAdd(2,-1)", async function () {
            let e;
            try {
                await testLibrary.decimalAdd(2, -1)
            } catch (error) {
                e = error
            }
            expect(e.reason).to.equal("value out-of-bounds")
        });

        it("decimalAdd(1,max-1) is max", async function () {
            expect(await testLibrary.decimalAdd(1, uintMax.sub(1))).to.equal(uintMax)
        });

        it("fail decimalAdd(1,max)", async function () {
            let e;
            try {
                await testLibrary.decimalAdd(1, uintMax)
            } catch (error) {
                e = error
            }
            expect(e).to.not.equal(undefined)
        });

        it("decimalMul(10,3) is 30", async function () {
            expect(await testLibrary.decimalMul(10, 3)).to.equal(30)
        });


        it("fail decimalMul(uintMax,2)", async function () {
            let e;
            try {
                await await testLibrary.decimalMul(uintMax, 2)
            } catch (error) {
                e = error
            }
            expect(e).to.not.equal(undefined)
        });

        it("fail decimalDiv(1,0)", async function () {
            let e;
            try {
                await testLibrary.decimalDiv(1, 0)
            } catch (error) {
                e = error
            }

            expect(e).to.not.equal(undefined)
        });

        it("decimalDiv(10,3) is 3", async function () {
            expect(await testLibrary.decimalDiv(10, 3)).to.equal(3)
        });

        it("decimalOppo(1) is -1", async function () {
            expect(await testLibrary.decimalOppo(1)).to.equal(-1)
        });

        it("decimalOppo(0) is 0", async function () {
            expect(await testLibrary.decimalOppo(0)).to.equal(0)
        });

        it("fail decimalOppo(uintMax)", async function () {
            let e;
            try {
                await testLibrary.decimalOppo(uintMax)
            } catch (error) {
                e = error
            }
            expect(e).to.not.equal(undefined)
        });
    })

    describe("signedDecimal.sol", function () {

        it("signedDecimalSub(2,1) is 1", async function () {
            expect(await testLibrary.signedDecimalSub(2, 1)).to.equal(1)
        });

        it("signedDecimalAdd(2,1) is 3", async function () {
            expect(await testLibrary.signedDecimalAdd(2, 1)).to.equal(3)
        });

        it("signedDecimalAddU(-1,2) is 1", async function () {
            expect(await testLibrary.signedDecimalAddU(-1, 2)).to.equal(1)
        });

        it("fail signedDecimalAdd(1,uintMax)", async function () {
            let e;
            try {
                await testLibrary.signedDecimalAdd(1, uintMax)
            } catch (error) {
                e = error
            }
            expect(e).to.not.equal(undefined)
        });

        it("signedDecimalMul(10,3) is 30", async function () {
            expect(await testLibrary.signedDecimalMul(10, 3)).to.equal(30)
        });

        it("fail signedDecimalMul(uintMax,2)", async function () {
            let e;
            try {
                await await testLibrary.signedDecimalMul(uintMax, 2)
            } catch (error) {
                e = error
            }
            expect(e).to.not.equal(undefined)
        });

        it("fail signedDecimalDiv(1,0)", async function () {
            let e;
            try {
                await testLibrary.signedDecimalDiv(1, 0)
            } catch (error) {
                e = error
            }

            expect(e).to.not.equal(undefined)
        });

        it("signedDecimalDiv(10,3) is 3", async function () {
            expect(await testLibrary.signedDecimalDiv(10, 3)).to.equal(3)
        });

    })
});
