# mesh-ecosystem-contracts

Smart contracts for the MeshEcosystem creator fee split on Robinhood Chain.

Projects that join the MeshEcosystem share 10 percent of their Pons v2 creator fees with the MeshGateway treasury. This repo contains the contracts that enforce that split on chain, so any project can verify the mechanism before joining and audit every payout after.

## How it works

Pons v2 pays creators in the pairing asset of their launch (native ETH for ETH paired launches). Fees build up as a claimable balance in the Pons fee escrow, held for the launch's creator fee recipient, and the recipient withdraws them with a manual claim. The recipient role itself is transferable: only the current recipient can pass it on, via the Pons launch factory.

```
Pons v2 fee escrow (claimable ETH balance per recipient)
        |
        v  claim()
  MeshSplitter  (one per project, set as the creator fee recipient)
        |
        +--> 10 percent  -> MeshGateway treasury
        +--> 90 percent  -> project payout wallet
```

1. MeshSplitterFactory deploys a `MeshSplitter` for the project, with the project's payout wallet and the fixed treasury share baked in.
2. The project's current fee recipient calls `transferCreatorFeeRecipient(token, splitter)` on the Pons launch factory. That is the only integration step on the project side. From then on creator fees credit to the splitter's escrow balance.
3. Anyone can call `claimAndRelease()` on the splitter. It claims the escrow balance and pays both parties in the same transaction.

## Trust properties

- The treasury address and the 10 percent share are immutable. They are set when the factory is deployed and no function exists to change them.
- Claiming and releasing are permissionless. If MeshGateway ever goes away, the project can still trigger its own 90 percent payout, and so can anybody else on its behalf.
- The project can leave at any time. The payout wallet can call `transferFeeRecipient(token, newRecipient)` on the splitter to move the Pons recipiency wherever it wants, without MeshGateway's involvement. Only fees claimed while the splitter held the role are subject to the split.
- The splitter never holds funds longer than one transaction when claimed through `claimAndRelease`, and any balance that arrives by other means is sweepable by anyone via `release`.
- The payout wallet can only be rotated by the current payout wallet.
- There is no owner, no upgrade path, and no pause switch on either contract.

Note: transferring the Pons recipiency also moves the buyback vest beneficiary, per the Pons factory implementation. Vested buyback tokens that arrive at the splitter are split like any other asset via `release(token)`.

## Contracts

| Contract | Description |
| --- | --- |
| `src/MeshSplitter.sol` | Per project fee splitter. Claims Pons v2 creator fees from the escrow and splits them 10/90. |
| `src/MeshSplitterFactory.sol` | Deploys splitters with the Pons contracts and treasury fixed. |
| `src/interfaces/IPonsV2.sol` | Minimal interfaces for the Pons v2 launch factory and fee escrow. |

External addresses on Robinhood Chain (chain id 4663):

| Name | Address |
| --- | --- |
| Pons v2 launch factory (`PonsV2LaunchFactory`) | `0x7eD598BcEf8bd9Edd8C97A195C6d13f40801EC7e` |
| Pons v2 fee escrow (`V2FeeEscrow`) | `0xd3AFEB2a57f70eF218Aa82451c51B2fb0416Ac9e` |

Deployed MeshEcosystem addresses will be listed here after mainnet deployment.

## Development

Built with [Foundry](https://getfoundry.sh).

```bash
forge build
forge test
```

Fork tests run the full flow against the live Pons v2 contracts, including transferring a real token's fee recipiency to a splitter, crediting the escrow, and claiming through the split:

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
