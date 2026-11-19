// AgentDrop — deployment configuration.
// The contract address is DETERMINISTIC (CREATE2 via the canonical proxy,
// salt keccak256("AgentDropBoard-v1"), owner = the agent wallet), so it is
// known before deployment. Confirm it is live (eth_getCode non-empty) before
// announcing. See ../DEPLOY-PATH.md and ../deploy/deploy-meta.json.
window.AGENTDROP_CONFIG = {
  chainId: 56,
  chainName: "BNB Smart Chain",
  rpcUrls: [
    "https://bsc-dataseed.binance.org",
    "https://bsc-dataseed1.defibit.io",
    "https://bsc.publicnode.com",
  ],
  explorerUrl: "https://bscscan.com",
  boardAddress: "0x4cfed72a30289d70B0036c81091C28C759726A1C",
  agentIdAddress: "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F",
  // Block the board was deployed in — set at deployment time so event scans
  // (My Badges / Leaderboard) start there instead of genesis.
  scanFromBlock: 134454193,
  logChunkSize: 5000,
};
