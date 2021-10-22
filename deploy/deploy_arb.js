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

  const L2Factory = await (
    await hre.ethers.getContractFactory('Factory')
  ).connect(l2Signer)
  const l2Factory = await L2Factory.deploy(
    '0xxx',
  )
  const result = await l2Factory.deployed()

  console.log(`deployed to ${l2Factory.address}`)
  console.log(result.deployTransaction.hash)
  console.log('✌️')
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error)
    process.exit(1)
  })
