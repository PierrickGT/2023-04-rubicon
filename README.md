# Rubicon v2 contest details
- Total Prize Pool: $60,500 USDC 
  - HM awards: $46,550 USDC 
  - QA report awards: $5,450 USDC 
  - Gas report awards: $2,500 USDC 
  - Judge awards: $5,500 USDC 
  - Lookout awards: Sponsor to complete Pre-sort
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-04-rubicon-v2/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts April 05, 2023 20:00 UTC
- Ends April 13, 2023 20:00 UTC 
- [Contest Overview Page from Sponsor](https://rubicondefi.notion.site/Rubicon-v2-Audit-Contest-b7b5b97393d14b068b6427522c779bfb)

## Automated Findings / Publicly Known Issues

Automated findings output for the contest can be found [here](https://gist.github.com/Picodes/01a3dd4b07d396e51b16fa758dad0fa5) within an hour of contest opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

# Overview

Rubicon v2 is the next generation of the Rubicon protocol, which has been live on Optimism for over a year. Try out our [app](https://app.rubicon.finance/swap), learn more about [Rubicon](https://www.rubicon.finance/), and read our [whitepaper](https://github.com/RubiconDeFi/rubicon-protocol-v1/blob/master/Rubicon%20v1%20Whitepaper.pdf) for added context. V2 overhauls the old Pools system, replacing it with a Compound V2 fork - leveraging over-collateralized lending/borrowing to enable cross-margin long/short trading on the protocol. The core of the protocol is `RubiconMarket`, an open order book contract that allows for limit and market orders for any arbitrary ERC20 trading pair of tokens. Paired with the new Pools system, we feel Rubicon v2 embodies two core primitives of the new financial era: the most efficient modality of exchange paired with a robust multi-collateral money market. Note that this protocol will be deployed on ETH L2 networks that are EVM equivalent, non-EVM L2s may require changes to the implementation.

# Scope

The following contracts are considered in scope for this audit. Here is the [codebase](https://github.com/code-423n4/2023-04-rubicon) for the audit, note that it includes some contracts outside of scope for helpful reference and for the testing suite to work.

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [contracts/RubiconMarket.sol](https://github.com/code-423n4/2023-04-rubicon/blob/main/contracts/RubiconMarket.sol) | 888 | Main order-book logic | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [contracts/BathHouseV2.sol](https://github.com/code-423n4/2023-04-rubicon/blob/main/contracts/BathHouseV2.sol) | 89 | Management of the BathTokens and BathBuddies | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [contracts/V2Migrator.sol](https://github.com/code-423n4/2023-04-rubicon/blob/main/contracts/V2Migrator.sol) | 30 | v1->v2 LPs migration | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [contracts/periphery/BathBuddy.sol](https://github.com/code-423n4/2023-04-rubicon/blob/main/contracts/periphery/BathBuddy.sol) | 143 | Rewards distribution for LPs | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [contracts/utilities/poolsUtility/Position.sol](https://github.com/code-423n4/2023-04-rubicon/blob/main/contracts/utilities/poolsUtility/Position.sol) | 360 | Creation of leveraged positions | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [contracts/utilities/FeeWrapper.sol](https://github.com/code-423n4/2023-04-rubicon/blob/main/contracts/utilities/FeeWrapper.sol) | 67 | Adding fees via 3rd party protocols | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |

Total nSLOC: 1577 - [calculated with this plugin.](https://github.com/ConsenSys/solidity-metrics)


## Out of scope

`contracts/compound-v2-fork/*.sol` and everything that isn't included in the scope above

# Additional Context

Rubicon V2 is a new version of the Rubicon Protocol. The Rubicon Pools system has undergone the biggest changes - the previous `ERC4626`-based liquidity pools have been replaced with Compound’s `cTokens`. The main functionality of the `RubiconMarket` remains the same, but minor changes were made. These include the addition of a new maker fee (rebate), changes to the `OfferInfo` struct, as well as minor changes to the `offer` functionality itself. All new features are described in more detail in the next section.

We wrap all contracts in `TransparentUpgradeableProxies` for upgradeability. On Optimism Mainnet, we will upgrade our `RubiconMarket` and `RubiconRouter` to the new implementations. For the market contract, there is a storage collision consideration we are aware of (please see Acknowledged Risks below) and the Router will not modify storage when upgraded. Please feel free to sanity-check our approach here!

## Contracts overview

### RubiconMarket

[Source code](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/master/contracts/RubiconMarket.sol)

This contract implements order-book logic for peer-to-peer trading of ERC-20 tokens and a matching engine. It is a derivative work of MakerDAO’s OasisDEX.

An order book is a list of buy and sell orders for an asset, sorted by price. This contract implements each ERC20/ERC20 order book as two double-linked sorted lists, one for the Buy-side and one for the Sell-side of the given market.

The contract uses an escrow model for liquidity; when a limit order is placed on the book, those tokens are sent to the contract. If/when an order is filled, the contract matches the traders directly and the tokens are sent to each party. An order can be canceled, and the contract will return the tokens to the sender.

### ***V1 to V2 Changeset:***

The core trading logic remains the same, while a few minor changes have been implemented, mainly for the accounting of fees, the `offer` interface, and the `OfferInfo` struct.

We moved towards fee inclusivity, i.e., the end user does not need to include the fee in their input amount to pay. New view functions for amount calculations with fee(s) were added: `getBuyAmountWithFee` and `getPayAmountWithFee`.

A new fee parameter, `makerFee`, is added to the market. In practice, this fee is paid by the taker to the maker when an `offer` is filled. To prevent storage collisions (because of the need to store `makerFee` exactly in one of the inherited contracts), the `makerFee` storage variable will be stored in a custom storage slot in `SimpleMarket`.

The `owner` field in the `OfferInfo` struct was replaced with `recipient`, and `owner` itself has been moved to the end of the struct. `recipient` now corresponds to the recipient of the `offer`'s fill, while `owner` refers to the owner and maker of that offer. It's worth noting that only the `owner` receives the `makerFee`, if one exists.

To smoothly perform an upgrade of the v1 market to v2, and taking into account the changes done to `OfferInfo` struct (that affects storage mapping - `offers`), certain functionality was added in the `cancel` and `buy` functions:

- [buy](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/34db36c71b170c8f13941ab26eb7ada1288ec82f/contracts/RubiconMarket.sol#L314)
    - `buy_gem` (an asset to buy), is now [transferred](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/34db36c71b170c8f13941ab26eb7ada1288ec82f/contracts/RubiconMarket.sol#L375) to the `recipient` instead of `owner`
    - `makerFee` is [transferred](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/34db36c71b170c8f13941ab26eb7ada1288ec82f/contracts/RubiconMarket.sol#L349) to the `owner` or in case of v1 offer to the `recipient` to avoid transferring tokens to `address(0)`
- [cancel](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/34db36c71b170c8f13941ab26eb7ada1288ec82f/contracts/RubiconMarket.sol#L452)
    - A new condition for cancelling an offer has been added to the `can_cancel` modifier. After upgrading, all outstanding offers that were created in v1 will have `owner == address(0)` and the `recipient` field will be equal to the `owner` field of the v1 `OfferInfo`. To handle the cancellation of v1 offers in v2, an offer can now be cancelled with `owner == address(0)` and `msg.sender == recipient`.
    - So, if the above scenario is given, then `pay_amt` will be transferred to the address that corresponds to the `recipient` of the offer.

### V2Migrator

[Source code](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/master/contracts/V2Migrator.sol)

Smart-contract, allowing to migrate LP positions from `ERC4626`-based v1 pool to the `cToken`-based v2 pool. Position could be migrated by the Rubicon v1 users, through the `migrate()` entry-point.

### BathHouse

[Source code](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/master/contracts/BathHouseV2.sol)

In v2-core, an administrative module that used to manage `BathTokens` and their respective `BathBuddies`
Contains functionality for the creation of `BathTokens` and their `BathBuddies` and claiming of rewards across all pools, using `claimComp` and `getReward`

***V1 to V2 Changeset:***

In contrast with the first version of `BathHouse` that was acting as an admin and liquidity manager for the Rubicon Pools system and allows access to the market making on Rubicon for actors called strategists, *the second version* of `BathHouse` integrates with the `Comptroller` contract, which now acts as a bath pools manager, while `BathHouse` more focused on higher-level functions for `BathTokens` and `BathBuddies` creation and linking, as well as allows easier access to the reward distribution  from both `BathToken` and `BathBuddy`.

### BathToken (cToken Fork)

[Source code](https://github.com/RubiconDeFi/rubi-protocol-v2/tree/master/contracts/compound-v2-fork), [compound docs](https://docs.compound.finance/v2/ctokens/#ctokens)

In v2-core – main pool primitive, that allows liquidity providers to earn passive yield, while market makers can borrow assets from the pool to execute active market-making strategies.

***V1 to V2 Changeset:***

`BathToken` in v2 is a fork of Compound’s `CToken` contract, which allows bringing together passive LPs and demand from borrowers.

### BathBuddy

[Source code](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/master/contracts/periphery/BathBuddy.sol)

Allows liquidity providers (bathToken holders) to earn additional ERC-20 token rewards.

***V1 to V2 changeset:***

In v2, `BathBuddy` is spawned upon deployment of each `BathToken`. The `getReward` function can now only be called through the `BathHouse`, either via `claimRewards()` (for claiming rewards across all existing pools) or via `getReward`(for claiming rewards in a specific target pool).

This is a conceptual fork and iteration of the SNX rewards distribution contract. We also used this in Pools v1. Note that in our old version, we had the claim function called in the low-level ERC20 functions of the Bath Token itself for automatic distribution. In v2 we remove this because we take the vanilla COMP v2 fork instead for that logic - please ensure that rewards cannot be stolen or incorrectly distributed by the bolt-on nature of a BathBuddy to a BathToken (cToken v2).

### Position

[Source code](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/master/contracts/utilities/poolsUtility/Position.sol)

This contract allows for the creation of the leveraged long/short positions on `RubiconMarket`, internally utilizing `cToken` functionality, continuously providing collateral and borrowing needed assets to reach a certain desired leverage amount.

Leveraged positions are cross-margined because the `cTokens` lending market itself is also cross-margined.

All positions are created via `PoolsUtility` factory contract. The created `Position` contract can then be used to create multiple leveraged positions.

All leveraged positions are opened by simple recursive borrowing loop (supply collateral → borrow → swap → repeat).

Both longs and shorts can be opened using `buyAllAmountWithLeverage` and `sellAllAmountWithLeverage`, respectively.

### FeeWrapper

[Source code](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/master/contracts/utilities/FeeWrapper.sol)

This contract allows any external smart contract to wrap calls to the Rubicon Protocol (actually it’s possible to wrap calls to any contract) and charge an additional fee. Examples of interactions with the FeeWrapper can be found in [Test3rdPartyProtocol.sol](https://github.com/RubiconDeFi/rubi-protocol-v2/blob/master/contracts/periphery/Test3rdPartyProtocol.sol)

# Points of Focus and Concern

- Ensuring `BathBuddy` is a secure way to distribute rewards to those lending and holding bathTokens (cToken fork)
    - In our past audit, we had calls to distribute these bonus token rewards in the low-level ERC20 functionality of our bath tokens - in this version we don’t do that due to simply taking the vanilla COMP v2 fork as is. Help us make sure rewards work correctly and cannot be hacked.
    - The idea is a `BathBuddy` is paired with a single cToken and if a rewards program is started on it, then any bathToken holder can claim rewards from the `BathBuddy` and our system over time
- *Ensuring that only the assigned admin of the system, a single EOA, has admin permissions* to modify fee logic, create bath tokens, and generally update the system
- Ensuring fee logic on `RubiconMarket` is bulletproof
- Ensuring the added implementation of batch calling functionality on `RubiconMarket` is secure
- Ensuring that users can easily perform levered long/short operations, with accuracy, using the combination of the new `Pools v2` - COMP v2 fork - system and `RubiconMarket`
- Ensuring in `BathHouseV2` that we are using the correct parts of the COMP v2 fork. For instance, in their repo, they have a number of versions of the Comptroller and we should adopt the best practices that they have keyed in on. Moreover, if there are known issues with this repo that could affect our implementation (however unlikely as this is somewhat of a Lindy system on L1) we would love to know
- Making that the correct version of COMP v2 was pulled for our fork - no modifications or deviations that are semantic should have been made

# Acknowledged Risks

- On Optimism Mainnet, we acknowledge that we are accepting a small risk when it comes to storage collision on the `RubiconMarket`. This stems from the extension of the low-level `offers` mapping and the `OfferInfo` struct.
    - For OP Mainnet, we plan to upgrade our `RubiconMarket` to the v2 implementation using the `TransparentUpgradeableProxy` pattern.
    - Note that according to our research, the chances of storage collision are quite low, driven by keccak256 behavior, close to that of getting struck by a meteor according to StackOverflow. Here are a couple of links that [explore this exact question](https://ethereum.stackexchange.com/questions/128484/mapped-struct-storage-layout-slots-and-collsions) and [where we sized up this “risk”](https://stackoverflow.com/questions/4014090/is-it-safe-to-ignore-the-possibility-of-sha-collisions-in-practice/4014407#4014407).
    - If you think this risk is not small enough to ignore as we do, please feel free to plead your case We feel it is near-zero that storage collision occurs here given we are only adding one property to the struct and the nature of mappings being stored in storage - if you disagree let’s discuss!
- The parameters supplied to the Pools v2 system are very important. We understand that adding low-liquidity, bad, or malicious tokens to the multi-collateral system invites risks into the entire system. We intend to only add blue-chip assets (e.g. WETH, WBTC, USDC, USDT, DAI) and to ensure we monitor the maximum liquidate-able value of each token on each chain we are on to implement borrowing caps. The Pools system must not grow to a size of borrows in which liquidators cannot remove the position in a healthy way. We plan to continuously monitor the system to make sure the right limits are in place.
- The admin has superpowers in our system - this is an acknowledged point of failure.

## Scoping Details

```
- If you have a public code repo, please share it here:  <https://github.com/RubiconDeFi/rubi-protocol-v2>
- How many contracts are in scope?:   6
- Total SLoC for these contracts?:  1577
- How many external imports are there?:  8
- How many separate interfaces and struct definitions are there for the contracts within scope?:  8
- Does most of your code generally use composition or inheritance?:   Composition
- How many external calls?:   5
- What is the overall line coverage percentage provided by your tests?:  60%
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?:   False
- Please describe required context:
- Does it use an oracle?:  Chainlink
- Does the token conform to the ERC20 standard?:
- Are there any novel or unique curve logic or mathematical models?: None - order books baby! Matching engine has some maths
- Does it use a timelock function?:
- Is it an NFT?:
- Does it have an AMM?:
- Is it a fork of a popular project?:
- Does it use rollups?:   True
- Is it multi-chain?:
- Does it use a side-chain?:

```

# Tests and Installation
Install dependencies
```shell
git clone --recurse-submodules https://github.com/code-423n4/2023-04-rubicon # clone the repo with HTTPS
git clone --recurse-submodules git@github.com:code-423n4/2023-04-rubicon.git # clone the repo with SSH
git submodule update --init --recursive # Updating with submodule if the repo was cloned without `--recurse-submodules`
npm i
yarn install # install deps
yarn run test # run tests
yarn run compile # compile
```
*OR*
```shell
# Cloning the repo using HTTPS
git clone --recurse-submodules https://github.com/code-423n4/2023-04-rubicon
# Cloning the repo using SSH
git clone --recurse-submodules git@github.com:code-423n4/2023-04-rubicon.git
# Updating with submodule if the repo was cloned without `--recurse-submodules`
git submodule update --init --recursive
# install deps
npm i
# run tests
npm run test 
# compile
npm run compile 
```
## Hardhat
```shell
yarn run test # run the test suite
yarn run compile # compile contracts
```
*OR*
```shell
npm run test # run the test suite
npm run compile # compile contracts
```
## Foundry
```shell
forge install
forge test # run the test suite
forge build # compile the contracts
```
