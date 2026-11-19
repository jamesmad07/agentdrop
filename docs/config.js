// AgentDrop — deployment configuration.
// The contract address is DETERMINISTIC (CREATE2 via the canonical proxy,
// salt keccak256("AgentDropBoard-v1"), owner = the agent wallet), so it is
// known before deployment. Confirm it is live (eth_getCode non-empty) before
// announcing. See ../DEPLOY-PATH.md and ../deploy/deploy-meta.json.
window.AGENTDROP_CONFIG = {
  chainId: 56,
  chainName: "BNB Smart Chain",
  // Read endpoints, tried in order with automatic failover (see app.js).
  // All of these answer CORS preflights with Access-Control-Allow-Origin: *
  // (verified from a browser Origin). NOTE: the PublicNode endpoint is
  // bsc-rpc.publicnode.com — the bare bsc.publicnode.com host is not an RPC
  // endpoint and returns 403. rpc.ankr.com/bsc is NOT listed on purpose: it
  // now rejects keyless requests. The last two entries are extra diversity
  // layers that are only reached when every endpoint above them has failed.
  rpcUrls: [
    "https://bsc-dataseed.binance.org",
    "https://bsc-rpc.publicnode.com",
    "https://bsc-dataseed1.defibit.io",
    "https://bsc-dataseed.bnbchain.org",
    "https://bsc-dataseed1.binance.org",
    "https://bsc.drpc.org",
    "https://bsc-mainnet.public.blastapi.io",
  ],
  explorerUrl: "https://bscscan.com",
  boardAddress: "0x4cfed72a30289d70B0036c81091C28C759726A1C",
  agentIdAddress: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
  // Block the board was deployed in — set at deployment time so event scans
  // (My Badges / Leaderboard) start there instead of genesis.
  scanFromBlock: 134454193,
  logChunkSize: 5000,
};
