const { expect } = require("chai");

describe("Margin contract", function () {
    let owner;
    let user1;
    let user2;
    let users;
    let mockBaseToken;
    let mockQuoteToken;
    let config;
    let factory;
    let router;
    let priceOracle;
    let amm;
    let margin;
    let vault;
    let staking;
    let currentTimeStamp;
    let ownerInitBaseAmount = 20000;
    let addr1InitBaseAmount = 100;
    let routerAllowance = 10000;
    let longSide = 0;
    let shortSide = 1;

    beforeEach(async function () {
        [owner, user1, user2, ...users] = await ethers.getSigners();

        // Deploy Mock Token
        const MockToken = await ethers.getContractFactory("MockToken");
        mockBaseToken = await MockToken.deploy("bit dao", "bit");
        mockQuoteToken = await MockToken.deploy("usdt dao", "usdt");

        // Mint BaseToken for owner
        await mockBaseToken.mint(owner.address,ethers.utils.parseEther('100000000.0'));

        // Mint QutoToken for owner
        await mockQuoteToken.mint(owner.address,ethers.utils.parseEther('100000000.0'));

        // Deploy Contract Config
        const Config = await ethers.getContractFactory("Config");
        config = await Config.deploy();

        // Deploy Factory
        const Factory = await ethers.getContractFactory("Factory");
        factory = await Factory.deploy(config.address);

        // Deploy Router
        const Router = await ethers.getContractFactory("Router");
        router = await Router.deploy(factory.address,mockBaseToken.address);

        // owner approve transfer mockBaseToken for router
        await mockBaseToken.approve(router.address,ethers.utils.parseEther('100000000.0'));

        // Deploy Oracle
        const PriceOracle = await ethers.getContractFactory("PriceOracleForTest");
        priceOracle = await PriceOracle.deploy();

        // PriceOracle set price
        await priceOracle.setReserve(mockBaseToken.address,mockQuoteToken.address,100,1000);

        // Set config 
        await config.setInitMarginRatio(909);
        await config.setLiquidateThreshold(10000);
        await config.setLiquidateFeeRatio(2000);
        await config.setPriceOracle(priceOracle.address);

        // Get currentTimeStamp
        currentTimeStamp = parseInt(new Date().getTime() / 1000);
    });

    async function initLiquidity(baseToken,quoteToken,baseAmount,quoteAmountMin,deadline,autoStake){
        // Call addLiquidity
        await router.addLiquidity(baseToken,quoteToken,baseAmount,quoteAmountMin,deadline,autoStake);

        // Get Amm address
        let ammAddress = await factory.getAmm(baseToken,quoteToken);
        let ammArtifact = artifacts.readArtifactSync("Amm");
        amm = new ethers.Contract(ammAddress,ammArtifact.abi,owner);
    
        //Get Margin address
        let marginAddress = await factory.getMargin(baseToken,quoteToken);
        let marginArtifact = artifacts.readArtifactSync("Margin");
        margin = new ethers.Contract(marginAddress,marginArtifact.abi,owner);

        //Get Vault address
        let vaultAddress = await factory.getVault(baseToken,quoteToken);
        let vaultArtifact = artifacts.readArtifactSync("Vault");
        vault = new ethers.Contract(vaultAddress,vaultArtifact.abi,owner); 
    }


    describe("Position", function () {
        it("Open position withWallet", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,true);  // liquid is 3162
            
            //console.log("totalSupply:" , ((await amm.totalSupply()).toString()));
            // Get Reserves
            let [baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();

            expect(baseReserve).to.be.equal(1000);
            expect(quoteReserve).to.be.equal(10000);

            await router.openPositionWithWallet(mockBaseToken.address,mockQuoteToken.address,1,1000,90,10**6,currentTimeStamp + 100);
            
            let position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.be.equal(90);
            expect(position[1]).to.be.equal(990);
            expect(position[2]).to.be.equal(10);
            
            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            expect(baseReserve).to.be.equal(1010);
            expect(quoteReserve).to.be.equal(9910);
            
            // Close partial position
            await router.closePosition(mockBaseToken.address,mockQuoteToken.address,10,currentTimeStamp + 100,false);
            
            position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.be.equal(80);
            expect(position[1]).to.be.equal(991);
            expect(position[2]).to.be.equal(9);
            
            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            expect(baseReserve).to.be.equal(1009);
            expect(quoteReserve).to.be.equal(9920);

            // Close total position
            await router.closePosition(mockBaseToken.address,mockQuoteToken.address,80,currentTimeStamp + 100,false);
            
            position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.be.equal(0);
            expect(position[1]).to.be.equal(999);
            expect(position[2]).to.be.equal(0);
            
            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            expect(baseReserve).to.be.equal(1001);
            expect(quoteReserve).to.be.equal(10000);
        });


        it("Close position with autoWithdraw", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,true);  
            
            //console.log("totalSupply:" , ((await amm.totalSupply()).toString()));
            // Get Reserves
            let [baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();

            expect(baseReserve).to.be.equal(1000);
            expect(quoteReserve).to.be.equal(10000);

            await router.openPositionWithWallet(mockBaseToken.address,mockQuoteToken.address,1,1000,90,10**6,currentTimeStamp + 100);
            
            let position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.be.equal(90);
            expect(position[1]).to.be.equal(990);
            expect(position[2]).to.be.equal(10);
            
            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            expect(baseReserve).to.be.equal(1010);
            expect(quoteReserve).to.be.equal(9910);

            // Close position
            await router.closePosition(mockBaseToken.address,mockQuoteToken.address,90,currentTimeStamp + 100,true);
            
            position = await margin.traderPositionMap(owner.address);
            expect(position[0]).to.be.equal(0);
            expect(position[1]).to.be.equal(0);
            expect(position[2]).to.be.equal(0);
            
            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            expect(baseReserve).to.be.equal(1001);
            expect(quoteReserve).to.be.equal(10000);

            // Check the balance of owner
            expect((await mockBaseToken.balanceOf(owner.address)).toString()).to.equal("99999999999999999999998999");
        });

    });

});
