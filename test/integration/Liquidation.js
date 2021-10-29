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
        await mockBaseToken.mint(owner.address,ethers.utils.parseEther('1000000.0'));
        await mockBaseToken.mint(user1.address,ethers.utils.parseEther('1000000.0'));

        // Mint QutoToken for owner
        await mockQuoteToken.mint(owner.address,ethers.utils.parseEther('1000000.0'));
        await mockQuoteToken.mint(user1.address,ethers.utils.parseEther('1000000.0'));

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
        await mockBaseToken.approve(router.address,ethers.utils.parseEther('100000.0'));
        let mockBaseToken1 = mockBaseToken.connect(user1);
        await mockBaseToken1.approve(router.address,ethers.utils.parseEther('100000.0'));

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


    describe("Liquidate", function () {
        it("Liquidate user's position", async function () {
            await initLiquidity(mockBaseToken.address,mockQuoteToken.address,ethers.utils.parseEther('10.0'),1,currentTimeStamp + 100,true);  // liquid is 3162
            
            //console.log("totalSupply:" , ((await amm.totalSupply()).toString()));
            // Get Reserves
            let [baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();

            console.log("baseReserve:",baseReserve.toString()," quoteReserve:",quoteReserve.toString()," blockTimestampLast",blockTimestampLast.toString())

            await router.openPositionWithWallet(mockBaseToken.address,mockQuoteToken.address,1,ethers.utils.parseEther('2.0'),ethers.utils.parseEther('2.0'),ethers.utils.parseEther('100000000.0'),currentTimeStamp + 100);
            
            let position = await margin.traderPositionMap(owner.address);
            console.log("quoteSize:" , position[0].toString());
            console.log("baseSize: ", position[1].toString());
            console.log("tradeSize:", position[2].toString());
            
            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            console.log("baseReserve:",baseReserve.toString()," quoteReserve:",quoteReserve.toString()," blockTimestampLast",blockTimestampLast.toString());

            // Liquidate
            console.log((await margin.calDebtRatio(position[0],position[1])).toString())

            let router1 = router.connect(user1);
            await router1.openPositionWithWallet(mockBaseToken.address,mockQuoteToken.address,1,1,20,ethers.utils.parseEther('100.0'),currentTimeStamp + 100);


            let position1 = await margin.traderPositionMap(user1.address);
            console.log("quoteSize:" , position1[0].toString());
            console.log("baseSize: ", position1[1].toString());
            console.log("tradeSize:", position1[2].toString());

            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            console.log("baseReserve:",baseReserve.toString()," quoteReserve:",quoteReserve.toString()," blockTimestampLast",blockTimestampLast.toString());

            console.log((await margin.calDebtRatio(position[0],position[1])).toString()); 
            /* await margin.liquidate(owner.address);
            
            console.log((await mockBaseToken.balanceOf(owner.address)).toString())
            position = await margin.traderPositionMap(owner.address);
            console.log("quoteSize:" , position[0].toString());
            console.log("baseSize: ", position[1].toString());
            console.log("tradeSize:", position[2].toString());
            
            ;[baseReserve,quoteReserve,blockTimestampLast] = await amm.getReserves();
            console.log("baseReserve:",baseReserve.toString()," quoteReserve:",quoteReserve.toString()," blockTimestampLast",blockTimestampLast.toString()); */
        });

    });

});
