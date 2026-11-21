# Security — AgentDrop

Board contract (BNB Smart Chain mainnet):
[`0x4cfed72a30289d70B0036c81091C28C759726A1C`](https://bscscan.com/address/0x4cfed72a30289d70B0036c81091C28C759726A1C)

## Security model

- **No custody, ever.** `claim` is `nonpayable`. The contract has no
  `receive`/`fallback`, no `withdraw`/`sweep`/`rescue`, and never requests
  token approvals from users. There is no code path that can move user
  funds or user assets.
- **The Agent ID gate cannot be weakened.** The official Agent ID contract
  address is a compile-time constant in the source. No function — owner or
  otherwise — can change it, bypass it, or mint around it.
- **Badges are minted only by the claimer, for themselves**, inside the
  public gated `claim` function. There is no owner mint, no team mint, and
  no hidden mint path.
- **Soulbound by design.** Every transfer or burn of an existing badge
  reverts in the ERC-721 `_update` hook. A badge is proof that a specific
  Agent ID holder personally claimed; making it transferable would destroy
  that meaning.
- **No upgrade path.** The contract is a single non-proxy deployment (the
  EIP-1967 implementation slot is empty), with no upgrade function and no
  selfdestruct.
- **Owner surface is exactly three functions** — `createDrop`,
  `setDropActive`, `setDropWindow` — fully documented in the README,
  including everything the owner *cannot* do. Ownership will be renounced
  after both live drops end (9 December 2026, 08:00 UTC).

## Verification status

- **BscScan:** source verified, "Pass - Verified" (19 November 2026).
- **Bytecode match:** the deployed runtime bytecode is byte-identical to
  the local Foundry build artifact of `src/AgentDropBoard.sol`.
- **Tests:** 22 Foundry tests pass, including deployment through the
  canonical CREATE2 Deterministic Deployment Proxy.
- **Sourcify:** no record yet; verification currently rests on BscScan
  plus the byte-exact runtime match above.

## Self-audit summary (20 November 2026)

A full self-audit was run against the deployed contract at a pinned block,
combining source review, on-chain state reads, and live simulations:

- Simulations confirmed the design end-to-end: transferring a badge
  reverts `Soulbound`; claiming without an Agent ID reverts
  `AgentIDRequired`; claiming twice reverts `AlreadyClaimed`.
- Selector/privilege review found no pause, no blacklist, no metadata
  setter, no owner mint, and no withdrawal path.
- A generic buyer-protection rubric scored the contract **45/100 with a
  BLOCK label**. We report this openly because the reason matters: the
  rubric's binding cap fires *solely* because badges are soulbound — the
  rubric is built for paid third-party mints where a buyer needs an exit.
  AgentDrop badges are free, nonpayable credentials; nothing a claimant
  paid can be trapped, and non-transferability is the product requirement.
  The audit's raw score before the soulbound cap was 78.5/100.
- Moderate findings, both accepted and disclosed: (1) a live owner holds
  the three documented drop-administration functions until renouncement
  after 9 December 2026; (2) this is a self-audit — no independent firm
  has reviewed the contract.

## Reporting

This is a hackathon project maintained by the agent identity kamala.ai.
Security observations are welcome via a GitHub issue in this repository.
Please do not include any credentials or private keys in a report.
