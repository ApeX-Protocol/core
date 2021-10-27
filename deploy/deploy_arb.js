const hre = require('hardhat')
const ethers = require('ethers')
const { Bridge } = require('arb-ts')
const { hexDataLength } = require('@ethersproject/bytes')
const { BigNumber } = require("@ethersproject/bignumber");

const walletPrivateKey = process.env.DEVNET_PRIVKEY

const l1Provider = new ethers.providers.JsonRpcProvider(process.env.L1RPC)
const l2Provider = new ethers.providers.JsonRpcProvider(process.env.L2RPC)
const signer = new ethers.Wallet(walletPrivateKey)

const l1Signer = signer.connect(l1Provider)
const l2Signer = signer.connect(l2Provider)
const configAddress = "0x7E20158e02C783894E402e15646D30E74ef9D6ed"
const factoryAddress = "0xcc030127843c477519c2211c4c820Ccc3b751DfF"
const baseAddress = "0x5819961755F120C71A02a020937a1bf0539ae53A"
const quoteAddress = "0x8b795AFfdaF2a18bd03B623Da74Cfc5ad9393443"
const routerAddress = "0x0A99dCEbA3FBD0C6A3c6607F6F1d8ec0e626a8De"
const priceOracleTestAddress = "0x5Fba840DFC744E60Af6fb8d749F911EBA80c26F5"
const l2Amm = "0xc16f9CC80e5bbb4E80F1F6AEdF7B33756Bd69c90"
const l2Margin = "0xeBe1E4F51113b560b647B5a0f8710095b7c4e1C7"
const l2Vault = "0x1fC4E7Fbc054312a0D576c8c3BfceC15536bd6c2"
const deadline = 1953397680

let l2Config
let l2BaseToken
let l2QuoteToken
let l2Weth
let l2Factory
let l2Router
let priceOracleForTest


const main = async () => {
  // await createContracts()
  await flowVerify(true)
}

async function createContracts() {
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
  l2Config = await L2Config.deploy()
  await l2Config.deployed()
  console.log(`l2Config: ${l2Config.address}`)
  //new mockToken base and quote
  l2BaseToken = await MockToken.deploy("base token", "bt")
  await l2BaseToken.deployed()
  console.log(`l2BaseToken: ${l2BaseToken.address}`)
  l2QuoteToken = await MockToken.deploy("quote token", "qt")
  await l2QuoteToken.deployed()
  console.log(`l2QuoteToken: ${l2QuoteToken.address}`)
  l2Weth = await MockToken.deploy("weth token", "wt")
  await l2Weth.deployed()
  console.log(`l2Weth: ${l2Weth.address}`)
  //new factory
  l2Factory = await L2Factory.deploy(l2Config.address)
  await l2Factory.deployed()
  console.log(`l2Factory: ${l2Factory.address}`)
  //new router
  l2Router = await L2Router.deploy(l2Factory.address, l2Weth.address)
  await l2Router.deployed()
  console.log(`l2Router: ${l2Router.address}`)
  //new PriceOracleForTest
  priceOracleForTest = await PriceOracleForTest.deploy()
  await priceOracleForTest.deployed()
  console.log(`priceOracleForTest: ${priceOracleForTest.address}`)

  //init set
  let tx = await l2Config.setPriceOracle(priceOracleForTest.address)
  await tx.wait()
  tx = await priceOracleForTest.setReserve(l2BaseToken.address, l2QuoteToken.address, 100, 200000)
  await tx.wait()
  tx = await l2BaseToken.mint(l2Signer.address, ethers.utils.parseEther('100000000.0'))
  await tx.wait()
  tx = await l2QuoteToken.mint(l2Signer.address, ethers.utils.parseEther('200000000.0'))
  await tx.wait()
  tx = await l2BaseToken.approve(l2Router.address, ethers.constants.MaxUint256)
  await tx.wait()
  tx = await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, ethers.utils.parseEther('10000.0'), 0, deadline, false)
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

  await flowVerify(false)
}

async function flowVerify(needAttach) {
  //attach
  if (needAttach) {
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

    l2Config = await L2Config.attach(configAddress)//exist config address
    l2Factory = await L2Factory.attach(factoryAddress)//exist factory address
    l2Router = await L2Router.attach(routerAddress)//exist router address
    l2BaseToken = await MockToken.attach(baseAddress)//exist base address
    l2QuoteToken = await MockToken.attach(quoteAddress)//exist quote address
    priceOracleForTest = await PriceOracleForTest.attach(priceOracleTestAddress)//exist priceOracleTest address
  }

  let tx;
  let positionItem;

  //flow 1
  console.log("add liquidity")
  tx = await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, ethers.utils.parseEther('1000.0'), 0, deadline, false)
  await tx.wait()
  tx = await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, ethers.utils.parseEther('1000.0'), 0, deadline, true)
  await tx.wait()
  console.log("deposit")
  tx = await l2Router.deposit(l2BaseToken.address, l2QuoteToken.address, l2Signer.address, ethers.utils.parseEther('1100.0'))
  await tx.wait()
  console.log("open position with margin")
  tx = await l2Router.openPositionWithMargin(l2BaseToken.address, l2QuoteToken.address, 0, ethers.utils.parseEther('100.0'), 0, deadline)
  await tx.wait()
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, l2Signer.address)
  console.log("after open, current quoteSize abs: ", BigNumber.from(positionItem[1]).abs().toString())
  tx = await l2Router.closePosition(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(positionItem[1]).abs(), deadline, false)
  await tx.wait()
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, l2Signer.address)
  console.log("after close, remain baseSize abs: ", BigNumber.from(positionItem[0]).abs().toString())
  console.log("withdraw")
  tx = await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(positionItem[0]).abs())
  await tx.wait()

  //flow 2
  console.log("add liquidity")
  tx = await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, ethers.utils.parseEther('1000.0'), 0, deadline, false)
  await tx.wait()

  tx = await l2Router.addLiquidity(l2BaseToken.address, l2QuoteToken.address, ethers.utils.parseEther('1000.0'), 0, deadline, true)
  await tx.wait()
  console.log("open position with wallet")
  tx = await l2Router.openPositionWithWallet(l2BaseToken.address, l2QuoteToken.address, 0, ethers.utils.parseEther('200.0'), ethers.utils.parseEther('200.0'), 0, deadline)
  await tx.wait()
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, l2Signer.address)
  console.log("after open, current quoteSize abs: ", BigNumber.from(positionItem[1]).abs().toString())
  tx = await l2Router.closePosition(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(positionItem[1]).abs(), deadline, false)
  await tx.wait()
  positionItem = await l2Router.getPosition(l2BaseToken.address, l2QuoteToken.address, l2Signer.address)
  console.log("after close, remain baseSize abs: ", BigNumber.from(positionItem[0]).abs().toString())
  console.log("withdraw")
  tx = await l2Router.withdraw(l2BaseToken.address, l2QuoteToken.address, BigNumber.from(positionItem[0]).abs())
  await tx.wait()
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
