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

const main = async () => {
  console.log('Deploying L2 Contract 👋👋')

  //config
  const L2Config = await (
    await hre.ethers.getContractFactory('Config')
  ).connect(l2Signer)
  const l2Config = await L2Config.deploy()
  await l2Config.deployed()
  console.log(`deployed l2Config to ${l2Config.address}`)

  //mockToken base and quote
  const MockToken = await (
    await hre.ethers.getContractFactory('MockToken')
  ).connect(l2Signer)
  const l2BaseToken = await MockToken.deploy("base token", "bt")
  await l2BaseToken.deployed()
  console.log(`deployed l2BaseToken to ${l2BaseToken.address}`)
  const l2QuoteToken = await MockToken.deploy("quote token", "qt")
  await l2QuoteToken.deployed()
  console.log(`deployed l2QuoteToken to ${l2QuoteToken.address}`)
  const l2Weth = await MockToken.deploy("weth token", "wt")
  await l2Weth.deployed()
  console.log(`deployed l2Weth to ${l2Weth.address}`)

  //factory
  const L2Factory = await (
    await hre.ethers.getContractFactory('Factory')
  ).connect(l2Signer)
  const l2Factory = await L2Factory.deploy(l2Config.address)
  await l2Factory.deployed()
  console.log(`deployed l2Factory to ${l2Factory.address}`)

  //router
  const L2Router = await (
    await hre.ethers.getContractFactory('Router')
  ).connect(l2Signer)
  const l2Router = await L2Router.deploy(l2Factory.address, l2Weth.address)
  await l2Router.deployed()
  console.log(`deployed l2Router to ${l2Router.address}`)

  //create pair
  const tx = await l2Factory.createPair(l2BaseToken.address,
    l2QuoteToken.address)
  await tx.wait()

  const l2Amm = await l2Factory.getAmm(l2BaseToken.address, l2QuoteToken.address)
  const l2Margin = await l2Factory.getMargin(l2BaseToken.address, l2QuoteToken.address)
  const l2Vault = await l2Factory.getVault(l2BaseToken.address, l2QuoteToken.address)
  console.log("l2Amm: ", l2Amm)
  console.log("l2Margin: ", l2Margin)
  console.log("l2Vault: ", l2Vault)
  console.log('✌️')
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
