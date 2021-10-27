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
        await mockBaseToken.mint(owner.address,10000);

        // Mint QutoToken for owner
        await mockQuoteToken.mint(owner.address,10000);

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
        await mockBaseToken.approve(router.address,10000);

        // Deploy Oracle
        const PriceOracle = await ethers.getContractFactory("MockPriceOracle");
        priceOracle = await PriceOracle.deploy();

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
        await router.addLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,autoStake);

        // Get Amm address
        let ammAddress = await factory.getAmm(mockBaseToken.address,mockQuoteToken.address);
        let ammArtifact = artifacts.readArtifactSync("Amm");
        amm = new ethers.Contract(ammAddress,ammArtifact.abi,owner);
    
        //Get Margin address
        let marginAddress = await factory.getMargin(mockBaseToken.address,mockQuoteToken.address);
        let marginArtifact = artifacts.readArtifactSync("Margin");
        margin = new ethers.Contract(marginAddress,marginArtifact.abi,owner);

        //Get Vault address
        let vaultAddress = await factory.getVault(mockBaseToken.address,mockQuoteToken.address);
        let vaultArtifact = artifacts.readArtifactSync("Vault");
        vault = new ethers.Contract(vaultAddress,vaultArtifact.abi,owner); 
    }

    describe("Liquidity", function () {
        /* it("Add liquidity at first success with autoStake", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,true)
            expect((await amm.totalSupply())).to.equal(10000000);
            
            // User LP balance should be correct
            expect((await amm.balanceOf(owner.address))).to.equal(10000000 - 1000);
        }); */

        /* it("Add liquidity at first success without autoStake", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,false)
            expect((await amm.totalSupply())).to.equal(10000000);
            
            let liquidity = 10000000 - 1000;
            expect((await amm.balanceOf(owner.address))).to.equal(liquidity);

            // Create Staking
            await factory.createStaking(mockBaseToken.address,mockQuoteToken.address);
            let stakeingAddress = await factory.getStaking(amm.address);

            // Approve for contract stake to transfer LP token
            await amm.approve(stakeingAddress,liquidity);

            // Staking mannually
            let stakeingArtifact = artifacts.readArtifactSync("Staking");
            staking = new ethers.Contract(stakeingAddress,stakeingArtifact.abi,owner);
            await staking.stake(liquidity);

            // Check staking result
            expect((await staking.balanceOf(owner.address))).to.equal(liquidity); 

        }); */

        /* it("Remove liquidity", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,false)
            expect((await amm.totalSupply())).to.equal(10000000);
            expect((await amm.balanceOf(owner.address))).to.equal(10000000 - 1000);
        }); */

    });

    describe("Open position", function () {
        it("Open position directly with calling Margin interface", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,1000,1,currentTimeStamp + 100,true)
            expect((await amm.totalSupply())).to.equal(10000000);
            
            // Open position
            let result = await margin.openPosition(1,1);
            console.log(result);
        });

    });

});
