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

    describe("Rebase", function () {
        it("Rebase the reserve", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,true)
            
            await priceOracle.setReserve(mockBaseToken.address,mockQuoteToken.address,12,13);

            await amm.rebase();

            let [baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();

            console.log("baseReserve:",baseReserve.toString()," quoteReserve:",quoteReserve.toString()," blockTimestampLast",blockTimestampLast.toString());

            // Check Reserve
            expect(baseReserve).to.be.equal(1000);
            expect(quoteReserve).to.be.equal(1083);
        });

    });

});
