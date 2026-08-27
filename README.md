# mesh-ecosystem-contracts

Smart contracts for the MeshEcosystem creator fee split on Robinhood Chain.

Projects that join the MeshEcosystem share 10 percent of their Pons v2 creator fees with the MeshGateway treasury. This repo contains the contracts that enforce that split on chain, so any project can verify the mechanism before joining and audit every payout after.

## How it works

Pons v2 accrues creator fees inside each token's locked liquidity position. The Pons launch locker pays the creator share to a configurable fee redirect address and lets that address trigger collection.

```
Pons locker (collectFees)
        |
        v
  MeshSplitter  (one per project, deployed by MeshSplitterFactory)
        |
        +--> 10 percent  -> MeshGateway treasury
        +--> 90 percent  -> project payout wallet
```

1. The factory deploys a `MeshSplitter` for the project, with the project's payout wallet and the fixed treasury share baked in.
2. The token deployer calls `setFeeRedirect(token, splitter)` on the Pons locker. That is the only integration step on the project side.
3. Anyone can call `claimAndRelease(token)` on the splitter. It collects the accrued fees from the locker (the locker authorizes it because the splitter is the fee recipient) and pays out both assets, the token and WETH, in the same transaction.

## Trust properties

- The treasury address and the 10 percent share are immutable. They are set when the factory is deployed and no function exists to change them.
- Releasing is permissionless. If MeshGateway ever goes away, the project can still trigger its own 90 percent payout, and so can anybody else on its behalf.
- The splitter never holds funds longer than one transaction when claimed through `claimAndRelease`, and any balance that arrives by other means is sweepable by anyone via `release`.
- The payout wallet can only be rotated by the current payout wallet.
- There is no owner, no upgrade path, and no pause switch on either contract.
- The project keeps full control of the redirect: the token deployer can point fees elsewhere at any time via the Pons locker. Membership benefits are tied to the redirect staying in place.

## Contracts

| Contract | Description |
| --- | --- |
| `src/MeshSplitter.sol` | Per project fee splitter. Collects Pons creator fees and splits them 10/90. |
| `src/MeshSplitterFactory.sol` | Deploys splitters with the locker and treasury fixed. |
| `src/interfaces/IPonsLaunchLocker.sol` | Minimal interface for the Pons v2 launch locker. |

External addresses on Robinhood Chain (chain id 4663):

| Name | Address |
| --- | --- |
| Pons v2 launch locker | `0x736D76699C26D0d966744cAe304C000d471f7F35` |
| WETH | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |

Deployed MeshEcosystem addresses will be listed here after mainnet deployment.

## Development

Built with [Foundry](https://getfoundry.sh).

```bash
forge build
forge test
```

Fork tests run the full flow against the live Pons locker, including setting a fee redirect as a token deployer and collecting real accrued fees:

```bash
forge test --fork-url https://rpc.mainnet.chain.robinhood.com
```

Deploy:

```bash
MESH_TREASURY=0x... forge script script/Deploy.s.sol \
  --rpc-url https://rpc.mainnet.chain.robinhood.com \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast --verify \
  --verifier blockscout \
  --verifier-url https://robinhoodchain.blockscout.com/api/
```

## License

MIT
