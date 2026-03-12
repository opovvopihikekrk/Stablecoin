# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ADCU (CorreaUSD) is an algorithmic, overcollateralized stablecoin system built with Foundry. It is pegged to USD and backed by WETH and WBTC as exogenous collateral. The design is similar to MakerDAO's DAI but with no governance and no fees.

## Build & Test Commands

```bash
forge build          # Compile contracts
forge test           # Run all tests
forge test -vvv      # Run tests with verbose output
forge test --mt testFunctionName  # Run a single test by name
forge test --mc ContractName      # Run all tests in a specific contract
forge fmt            # Format Solidity code
forge fmt --check    # Check formatting without modifying
forge snapshot       # Generate gas snapshots
```

CI runs `forge fmt --check`, `forge build --sizes`, and `forge test -vvv`.

## Architecture

**Core contracts (`src/`):**
- `StableCoin.sol` — ERC20 token ("CorreaUSD" / "ADCU"). Ownable, with mint/burn restricted to the owner (the engine). Extends OpenZeppelin's ERC20Burnable.
- `ADCUEngine.sol` — Core protocol logic. Manages collateral deposits/withdrawals, ADCU minting/burning, and liquidations. Enforces overcollateralization via a health factor system (50% liquidation threshold, 10% liquidation bonus). Uses `ReentrancyGuard` on all state-changing functions.
- `Libraries/OracleLib.sol` — Library used on Chainlink `AggregatorV3Interface` to revert on stale price data (3-hour timeout).

**Key invariant:** Total collateral value (in USD) must always exceed total ADCU supply.

**Health factor:** `(collateralUSD * 50 / 100) * 1e18 / totalADCUMinted`. Must stay >= 1e18 or the user can be liquidated.

**Deployment (`script/`):**
- `DeployADCU.s.sol` — Deploys StableCoin + ADCUEngine, transfers StableCoin ownership to the engine.
- `HelperConfig.s.sol` — Network config for Sepolia (chainid 11155111) and local Anvil (chainid 31337). Anvil config deploys mock price feeds and ERC20 tokens.

**Tests (`test/`):**
- `unit/ADCUEngineTest.t.sol` — Unit tests using DeployADCU for setup. Uses `MockV3Aggregator` to simulate price drops for liquidation tests.
- `fuzz/Handler.t.sol` — Fuzz handler that bounds inputs for deposit, redeem, and mint operations.
- `fuzz/Invariants.t.sol` — Invariant test asserting protocol solvency. Configured with 128 runs and 128 depth in `foundry.toml`.

## Dependencies

Managed as git submodules in `lib/`:
- `forge-std`
- `openzeppelin-contracts` (remapped as `@openzeppelin`)
- `chainlink-brownie-contracts` (remapped as `@chainlink`)

Solidity version: `^0.8.19`
