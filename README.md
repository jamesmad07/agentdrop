# AgentDrop

**AgentDrop** is a free-claim board built exclusively for **Agent ID**
holders, created for the Agent ID Hackathon (Binance Wallet × BNB Chain).

Projects list time-boxed "drops" on the board. A wallet that holds an Agent
ID can claim **one soulbound badge per drop**, and the badge is bound
on-chain to the claimer's `.ai` handle. Because an Agent ID is
one-per-Binance-user and non-transferable, every drop is structurally
one-person-one-claim — no separate allowlist, no off-chain Sybil filtering.

- **Live board contract (BNB Smart Chain mainnet):**
  [`0x4cfed72a30289d70B0036c81091C28C759726A1C`](https://bscscan.com/address/0x4cfed72a30289d70B0036c81091C28C759726A1C)
- **Official Agent ID contract (BNB Smart Chain):**
  `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
- **Claim site (live):** https://jamesmad07.github.io/agentdrop/
  (source in this repository's `docs/` folder, served via GitHub Pages)
- **Contract:** `src/AgentDropBoard.sol` — a single contract, not
  upgradeable, no proxy
- **License:** MIT · Solidity ^0.8.24 (built with solc 0.8.26) ·
  OpenZeppelin Contracts v5.1.0

## The problem AgentDrop solves

Free drops and allowlist claims are normally Sybil games: one person runs
fifty wallets and takes fifty slots, while the project pays for off-chain
filtering that never quite works. Agent ID changes the primitive — it is a
verified, non-transferable, one-per-Binance-user identity that already
lives on-chain. AgentDrop builds distribution directly on that primitive:
the identity check *is* the allowlist, enforced by the contract itself on
every claim. No sign-up forms, no wallet-list snapshots, no off-chain
trust. Any project that wants fair, one-per-person distribution to the
Agent ID ecosystem gets it from a single `createDrop` call (listing is
owner-mediated in this v1 board).

## Live traction

On-chain snapshot, 21 November 2026 (independently reproducible — see
"Verify it yourself" below):

| Metric | Value |
| --- | --- |
| Badges claimed | **35** |
| Unique Agent ID holders who claimed | **32** |
| Drop #0 "Genesis" | 13 / 500 claimed |
| Drop #1 "Second Wave" | 22 / 500 claimed |
| Innovation-track threshold (≥ 30 unique Agent ID addresses) | **Met** |
| Growth | 14 → 32 unique claimers in ~24 hours |

Both drops are open until 9 December 2026, 08:00 UTC. Every claimer is a
verified Agent ID holder by construction: the contract reverts any claim
from a wallet that does not hold an Agent ID, and enforces one claim per
address per drop.

**Verify it yourself:** call `totalBadges()` and `getDrop(0)` /
`getDrop(1)` on the
[board contract](https://bscscan.com/address/0x4cfed72a30289d70B0036c81091C28C759726A1C),
or iterate `ownerOf(tokenId)` for tokenIds 1–35 — because badges are
soulbound, each owner is exactly the Agent ID holder who claimed it.

## How the Agent ID gate works

Every `claim(dropId)` call, in order:

1. checks the drop exists, is active, is inside its time window, is not
   sold out, and has not already been claimed by the caller;
2. requires `AGENT_ID.balanceOf(msg.sender) > 0` against the **official
   Agent ID contract** — the address is a compile-time constant in the
   source, so the gate cannot be changed after deployment;
3. reads the claimer's handle via `AGENT_ID.handleOf(msg.sender)`;
4. mints a soulbound badge and records `(dropId, claimer, tokenId, handle)`
   in the permanent `Claimed` event.

A wallet without an Agent ID simply cannot claim — the transaction reverts
with `AgentIDRequired()`.

## Owner permissions — complete disclosure

The owner is the project's Agentic Wallet (`kamala.ai`). The owner can do
**exactly three things**, plus standard Ownable ownership transfer:

| Capability | Function | Notes |
| --- | --- | --- |
| Create a drop | `createDrop(name, metadataURI, startTime, endTime, maxClaims)` | Name ≤ 64 bytes, URI ≤ 256 bytes, `startTime < endTime` |
| Activate / deactivate a drop | `setDropActive(dropId, active)` | E.g. to retire a drop with bad metadata |
| Correct a drop's schedule | `setDropWindow(dropId, startTime, endTime)` | Window validity is enforced |

The owner **cannot**:

- mint a badge for anyone (badges are minted only inside `claim`, by the
  claimer, for themselves);
- change, weaken, or bypass the Agent ID gate (compile-time constant);
- alter, cancel, or reassign a claim that already happened;
- take, move, or burn anyone's badge (all transfers and burns revert);
- withdraw funds — the contract has no `receive`/`fallback` and **no
  withdraw function of any kind**; `claim` is nonpayable, so the contract
  never takes custody of user funds;
- upgrade the contract — there is no proxy, no upgrade path, and no
  selfdestruct.

**No token approvals are ever requested from users.** The only user
interaction is a single `claim` transaction costing only network gas
(≈ $0.003).

Badges are **soulbound collectibles**: every transfer or burn reverts in the
ERC-721 `_update` hook. They are non-transferable memorabilia — **no value,
returns, yield, or profit of any kind are promised or implied**.

## Security summary

- Source code is **verified on BscScan** ("Pass - Verified"), and the
  deployed runtime bytecode is byte-identical to the local Foundry build
  artifact of the source in this repository.
- A documented **self-audit** (20 November 2026) reviewed the deployed
  contract on-chain and in source: claim path, privilege surface, custody,
  and the soulbound design. Its summary — including the honest note that a
  generic buyer-protection rubric caps the score *because* the badges are
  soulbound by design, while no claimant funds are ever at risk — is in
  [SECURITY.md](SECURITY.md).
- The board passed a **22-test Foundry suite**, including deployment
  through the canonical CREATE2 Deterministic Deployment Proxy.
- Ownership is scheduled to be **renounced after both drops end**
  (9 December 2026, 08:00 UTC), permanently removing the three documented
  owner capabilities once no drop administration is needed anymore.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/AgentDropBoard.sol` | The board contract (the deployed source) |
| `test/` | Foundry test suite (`AgentDropBoard.t.sol`, `MockAgentID.sol`) — 22 tests |
| `foundry.toml` | Foundry profile (solc 0.8.26, optimizer 200 runs) |
| `docs/` | The static claim site (plain HTML/CSS/JS, standard injected wallet connection — no pairing codes, no session handover) |
| `SECURITY.md` | Security model and self-audit summary |
| `LICENSE` | MIT license |

## Build & test

```sh
forge install   # fetch OpenZeppelin Contracts + forge-std into lib/
forge build
forge test      # 22 tests, including deployment through the canonical
                # CREATE2 Deterministic Deployment Proxy
```

## Deployment

The board was deployed deterministically (CREATE2) through the canonical
Deterministic Deployment Proxy
(`0x4e59b44847b379578588920cA78FbF26c0B4956C`) with
`salt = keccak256("AgentDropBoard-v1")`, so the mainnet address above was
known before deployment and is reproduced by the test suite. The constructor
argument `initialOwner` is the owner wallet, passed explicitly because the
immediate deployer through the proxy would otherwise become the owner.

## Compliance checklist

- [x] Deployed on BNB Smart Chain; source code public in this repository
- [x] Actively uses Agent ID as the claim gate (on-chain `balanceOf` +
      `handleOf` against the official contract)
- [x] Standard injected wallet connection only — no QR / pairing-code login
      flows, no session handover
- [x] Users confirm their own transactions; no prompt bypasses user
      confirmation
- [x] No hidden transfers or approvals — the contract requests zero token
      approvals and cannot receive or move user funds
- [x] Owner permissions fully documented (table above)
- [x] No impersonation of "Binance" / "BNB" branding in the project name,
      token, or materials
- [x] No promises of returns — badges are stated everywhere as
      non-transferable collectibles with no monetary value
- [x] Not a trading product; no risk warnings applicable
- [x] No name→wallet lookup feature — the site never resolves other
      people's names to their wallets
- [x] No manufactured volume or mass accounts — claims come only from real
      Agent ID holders claiming for themselves, one per drop
