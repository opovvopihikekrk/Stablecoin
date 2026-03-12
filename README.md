# ADCU - Algorithmic Decentralized Collateralized USD

An algorithmic, overcollateralized stablecoin system built with Foundry. ADCU is pegged to USD and backed by WETH and WBTC as exogenous collateral. Similar to MakerDAO's DAI but with no governance and no fees.

## Deployed on Sepolia

| Contract | Address |
|----------|---------|
| ADCUEngine | [`0x6cd6d89c1358b2a9802c6b8bd39a8b9b2039f927`](https://sepolia.etherscan.io/address/0x6cd6d89c1358b2a9802c6b8bd39a8b9b2039f927) |

## How It Works

Users deposit WETH or WBTC as collateral and mint ADCU tokens (1 ADCU = $1). The system enforces overcollateralization at all times:

- **Liquidation Threshold:** 50% — your minted ADCU can be worth at most half of your collateral value in USD
- **Liquidation Bonus:** 10% — liquidators receive a 10% bonus on the collateral they claim
- **Health Factor:** Must stay >= 1. If it drops below 1, anyone can liquidate your position
- **Price Feeds:** Chainlink oracles with a 3-hour staleness check

### Example

Deposit $2,000 worth of WETH → you can mint up to 1,000 ADCU. If ETH price drops and your collateral falls below 2x your minted ADCU, you become liquidatable.

## Architecture

```
src/
├── StableCoin.sol          — ERC20 token ("ADCU"). Mint/burn restricted to the engine (owner).
├── ADCUEngine.sol          — Core protocol: deposits, withdrawals, minting, burning, liquidations.
└── Libraries/OracleLib.sol — Chainlink price feed staleness check (3h timeout).

script/
├── DeployADCU.s.sol        — Deploys StableCoin + ADCUEngine, transfers ownership to engine.
└── HelperConfig.s.sol      — Network config for Sepolia and local Anvil.

test/
├── unit/ADCUEngineTest.t.sol   — Unit tests for all engine operations.
└── fuzz/
    ├── Handler.t.sol           — Fuzz handler bounding inputs for deposit, redeem, mint.
    └── Invariants.t.sol        — Invariant: total collateral value > total ADCU supply.
```

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Install dependencies, clean, and build

```bash
make all
```

### Build

```bash
forge build
```

### Test

```bash
forge test           # Run all tests
forge test -vvv      # Verbose output
forge test --mt testFunctionName  # Run a single test
forge test --mc ContractName      # Run tests in a specific contract
```

### Format

```bash
forge fmt
```

### Deploy (local Anvil)

```bash
anvil
forge script script/DeployADCU.s.sol --rpc-url http://localhost:8545 --broadcast
```

## Dependencies

- [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) — ERC20, Ownable, ReentrancyGuard
- [Chainlink Brownie Contracts](https://github.com/smartcontractkit/chainlink-brownie-contracts) — AggregatorV3Interface price feeds
- [Forge Std](https://github.com/foundry-rs/forge-std) — Foundry testing utilities

## License

MIT
