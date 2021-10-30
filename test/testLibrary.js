const { BigNumber } = require("@ethersproject/bignumber");
const { expect } = require("chai");

describe("Library contract", function () {
  let testLibrary;
  let uintMaxHex = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"; //2^256-1
  let uintMax = BigNumber.from(uintMaxHex);
  let intMaxStr = "0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"; //2^255-1
  let intMax = BigNumber.from(intMaxStr);
  let uintMinHex = "0x0"; //0
  let uintMin = BigNumber.from(uintMinHex);
  let intMinStr = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"; //-2^255
  let intMin = BigNumber.from(intMinStr);

  beforeEach(async function () {
    const TestLibrary = await ethers.getContractFactory("TestLibrary");
    testLibrary = await TestLibrary.deploy();
  });

  describe("math.sol", function () {
    it("min(1,2) is 1", async function () {
      expect(await testLibrary.mathMin(1, 2)).to.equal(1);
    });

    it("min(-1,2) is -1", async function () {
      expect(await testLibrary.mathMin(-1, 2)).to.equal(-1);
    });

    it("minU(1,2) is 1", async function () {
      expect(await testLibrary.mathMinU(1, 2)).to.equal(1);
    });

    it("minU(1,uintMax) is 1", async function () {
      expect(await testLibrary.mathMinU(1, uintMax)).to.equal(1);
    });
  });

  describe("signedDecimal.sol", function () {
    it("signedDecimalSub(2,1) is 1", async function () {
      expect(await testLibrary.signedDecimalSub(2, 1)).to.equal(1);
    });

    it("signedDecimalSub(-2,-1) is -1", async function () {
      expect(await testLibrary.signedDecimalSub(-2, -1)).to.equal(-1);
    });

    it("signedDecimalAdd(2,1) is 3", async function () {
      expect(await testLibrary.signedDecimalAdd(2, 1)).to.equal(3);
    });

    it("signedDecimalAddU(-1,2) is 1", async function () {
      expect(await testLibrary.signedDecimalAddU(-1, 2)).to.equal(1);
    });

    it("signedDecimalAddU(1,intMax-1) is intMax", async function () {
      expect(await testLibrary.signedDecimalAddU(1, intMax.sub(1))).to.equal(intMax);
    });

    it("fail signedDecimalAddU(1,intMax+1), reverted", async function () {
      await expect(testLibrary.signedDecimalAddU(1, intMax.add(1))).to.be.revertedWith("overflow");
    });

    it("fail signedDecimalAddU(1,intMax)", async function () {
      let e;
      try {
        await testLibrary.signedDecimalAddU(1, intMax);
      } catch (error) {
        e = error;
      }
      expect(e).to.not.equal(undefined);
    });

    it("fail signedDecimalAddU(1,uintMax)", async function () {
      let e;
      try {
        await testLibrary.signedDecimalAddU(1, uintMax);
      } catch (error) {
        e = error;
      }
      expect(e).to.not.equal(undefined);
    });

    it("signedDecimalMul(10,3) is 30", async function () {
      expect(await testLibrary.signedDecimalMul(10, 3)).to.equal(30);
    });

    it("fail signedDecimalMul(uintMax,2)", async function () {
      let e;
      try {
        await await testLibrary.signedDecimalMul(uintMax, 2);
      } catch (error) {
        e = error;
      }
      expect(e).to.not.equal(undefined);
    });

    it("fail signedDecimalDiv(1,0)", async function () {
      let e;
      try {
        await testLibrary.signedDecimalDiv(1, 0);
      } catch (error) {
        e = error;
      }

      expect(e).to.not.equal(undefined);
    });

    it("signedDecimalDiv(10,3) is 3", async function () {
      expect(await testLibrary.signedDecimalDiv(10, 3)).to.equal(3);
    });
  });
});
