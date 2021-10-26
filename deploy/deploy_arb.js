const hre = require('hardhat')
const ethers = require('ethers')
const { Bridge } = require('arb-ts')
const { hexDataLength } = require('@ethersproject/bytes')

const walletPrivateKey = process.env.DEVNET_PRIVKEY

const l1Provider = new ethers.providers.JsonRpcProvider(process.env.L1RPC)
const l2Provider = new ethers.providers.JsonRpcProvider(process.env.L2RPC)
const signer = new ethers.Wallet(walletPrivateKey)

const l1Signer = signer.connect(l1Provider)
const l2Signer = signer.connect(l2Provider)
const configAddress = "0x5567d1247b79d918068e17d9c9fAd48369806D2d"
const factoryAddress = "0x3529d2280D0D8068d7B6D10E75607Cd89B211880"
const baseAddress = "0xD4c652999084ef502Cbe6b0a2bD7277b7dab092E"
const quoteAddress = "0xAd4215344396F4B53AaF7B494Cc3580E8CF14104"
const routerAddress = "0x3604B592886b137aab1e1Af29566a29874907265"
const priceOracleTestAddress = "0x2458e6BD0CC06E42cC9F9205eb0a8b40C6dd9C39"
const l2Amm = "0x1b26081379502fFC39f64c88B6196be588017268"
const l2Margin = "0x2949236bd977DD3Db262a3957E0692acbD473d33"
const l2Vault = "0x605c5B08Cb4819550CBa58D7cB697CDE1fBd670F"
const deadline = 1953397680

const main = async () => {
  await firstCreate()
  // await secondSet()
}

async function firstCreate() {
  console.log('Deploying L2 Contract 👋👋')
  const L2Config = await (
    await hre.ethers.getContractFactory('Config')
  ).connect(l2Signer)
  const MockToken = await (
    await hre.ethers.getContractFactory('MockToken')
  ).connect(l2Signer)
  const L2Factory = await (
    await hre.ethers.getContractFactory('Factory')
  ).connect(l2Signer)
  const L2Router = await (
    await hre.ethers.getContractFactory('Router')
  ).connect(l2Signer)
  const L2PriceOracle = await (
    await hre.ethers.getContractFactory('PriceOracle')
  ).connect(l2Signer)
  const PriceOracleForTest = await (
    await hre.ethers.getContractFactory('PriceOracleForTest')
  ).connect(l2Signer)

  //new config
  const l2Config = await L2Config.deploy()
  await l2Config.deployed()
  console.log(`l2Config: ${l2Config.address}`)
  //new mockToken base and quote
  const l2BaseToken = await MockToken.deploy("base token", "bt")
  await l2BaseToken.deployed()
  console.log(`l2BaseToken: ${l2BaseToken.address}`)
  const l2QuoteToken = await MockToken.deploy("quote token", "qt")
  await l2QuoteToken.deployed()
  console.log(`l2QuoteToken: ${l2QuoteToken.address}`)
  const l2Weth = await MockToken.deploy("weth token", "wt")
  await l2Weth.deployed()
  console.log(`l2Weth: ${l2Weth.address}`)
  //new factory
  const l2Factory = await L2Factory.deploy(l2Config.address)
  await l2Factory.deployed()
  console.log(`l2Factory: ${l2Factory.address}`)
  //new router
  const l2Router = await L2Router.deploy(l2Factory.address, l2Weth.address)
  await l2Router.deployed()
  console.log(`l2Router: ${l2Router.address}`)
  //new PriceOracleForTest
  const priceOracleForTest = await PriceOracleForTest.deploy()
  await priceOracleForTest.deployed()
  console.log(`priceOracleForTest: ${priceOracleForTest.address}`)

  // let tx = await l2Router.createPair(l2BaseToken.address, l2QuoteToken.address)
  // await tx.wait()

  //init set
  let tx = await l2Config.setPriceOracle(priceOracleForTest.address)
  await tx.wait()
  tx = await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 100, 200000)
  await tx.wait()
  tx = await l2BaseToken.mint(l2Signer.address, "100000000000000000000000000")
  await tx.wait()
  tx = await l2QuoteToken.mint(l2Signer.address, "200000000000000000000000000")
  await tx.wait()
  tx = await l2BaseToken.approve(l2Router.address, "10000000000000000000000000000")
  await tx.wait()
  tx = await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, "10000000000000000000000", 0, deadline, false)
  await tx.wait()


  const l2Amm = await l2Factory.getAmm(l2BaseToken.address, l2QuoteToken.address)
  const l2Margin = await l2Factory.getMargin(l2BaseToken.address, l2QuoteToken.address)
  const l2Vault = await l2Factory.getVault(l2BaseToken.address, l2QuoteToken.address)
  console.log("l2Amm: ", l2Amm)
  console.log("l2Margin: ", l2Margin)
  console.log("l2Vault: ", l2Vault)
  console.log('✌️')
  console.log("npx hardhat verify --network l2 " + l2Config.address)
  console.log("npx hardhat verify --network l2 " + l2Factory.address + " " + l2Config.address)
  console.log("npx hardhat verify --network l2 " + l2Router.address + " " + l2Factory.address + " " + l2Weth.address)
  console.log("npx hardhat verify --network l2 " + l2BaseToken.address + " 'base token' 'bt'")
  console.log("npx hardhat verify --network l2 " + l2QuoteToken.address + " 'quote token' 'qt'")
  console.log("npx hardhat verify --network l2 " + l2Weth.address + " 'weth token' 'wt'")
  console.log("npx hardhat verify --network l2 " + priceOracleForTest.address)
}


async function secondSet() {
  const L2Config = await (
    await hre.ethers.getContractFactory('Config')
  ).connect(l2Signer)
  const MockToken = await (
    await hre.ethers.getContractFactory('MockToken')
  ).connect(l2Signer)
  const L2Factory = await (
    await hre.ethers.getContractFactory('Factory')
  ).connect(l2Signer)
  const L2Router = await (
    await hre.ethers.getContractFactory('Router')
  ).connect(l2Signer)
  const L2PriceOracle = await (
    await hre.ethers.getContractFactory('PriceOracle')
  ).connect(l2Signer)
  const PriceOracleForTest = await (
    await hre.ethers.getContractFactory('PriceOracleForTest')
  ).connect(l2Signer)


  //attach
  const l2Config = await L2Config.attach(configAddress)//exist config address
  const l2Factory = await L2Factory.attach(factoryAddress)//exist factory address
  const l2Router = await L2Router.attach(routerAddress)//exist router address
  const l2BaseToken = await MockToken.attach(baseAddress)//exist base address
  const l2QuoteToken = await MockToken.attach(quoteAddress)//exist quote address
  const priceOracleForTest = await PriceOracleForTest.attach(priceOracleTestAddress)//exist priceOracleTest address

  //read
  const amm = await l2Factory.getAmm(l2BaseToken.address, l2QuoteToken.address)
  console.log("amm: ", amm)
  const stake = await l2Factory.getStaking(amm)
  console.log("stake: ", stake)

  //set
  await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, 100000000, 0, deadline, false)
  await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, 100000000, 0, deadline, true)
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
