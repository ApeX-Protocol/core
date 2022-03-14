# ApeX Protocol

Contracts for DEX.

## Install Dependencies
npm install

## Compile Contracts
npm run compile

## Run Tests
npm run test
npx hardhat test ./test/amm.js


## Run Deploy
> set .env

npm run deploy_arb


reference deploy: npx hardhat run scripts/deploy_reference.js --network l2rinkeby

## Simulation

`npx hardhat test test/simulation.js`

`bash plot.sh sim_50_3000.csv`
