import { ethers } from "https://cdn.jsdelivr.net/npm/ethers@6.13.4/dist/ethers.min.js";

const CFG = window.AGENTDROP_CONFIG;

const BOARD_ABI = [
  "function dropCount() view returns (uint256)",
  "function getDrop(uint256) view returns (tuple(string name, string metadataURI, uint64 startTime, uint64 endTime, uint32 maxClaims, uint32 claimCount, bool active))",
  "function hasClaimed(uint256, address) view returns (bool)",
  "function balanceOf(address) view returns (uint256)",
  "function claim(uint256) nonpayable",
  "event Claimed(uint256 indexed dropId, address indexed claimer, uint256 indexed tokenId, string handle)",
];
const AGENT_ID_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function handleOf(address) view returns (string)",
];

const readProvider = new ethers.JsonRpcProvider(CFG.rpcUrls[0]);
const boardRead = new ethers.Contract(CFG.boardAddress, BOARD_ABI, readProvider);
const agentIdRead = new ethers.Contract(CFG.agentIdAddress, AGENT_ID_ABI, readProvider);

let signer = null;
let account = null;
let isHolder = false;

const $ = (id) => document.getElementById(id);
const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
$("boardLink").href = `${CFG.explorerUrl}/address/${CFG.boardAddress}`;

function fmtWindow(d) {
  const f = (t) => new Date(Number(t) * 1000).toUTCString().replace("GMT", "UTC");
  return `${f(d.startTime)} → ${f(d.endTime)}`;
}

function dropState(d, now) {
  if (!d.active) return "inactive";
  if (now < Number(d.startTime)) return "upcoming";
  if (now > Number(d.endTime)) return "ended";
  if (d.maxClaims > 0 && d.claimCount >= d.maxClaims) return "soldout";
  return "live";
}

async function renderDrops() {
  const el = $("drops");
  try {
    const count = Number(await boardRead.dropCount());
    if (count === 0) {
      el.innerHTML = '<p class="muted">No drops yet. The first drop opens at launch.</p>';
      return;
    }
    const now = Math.floor(Date.now() / 1000);
    const cards = [];
    for (let i = 0; i < count; i++) {
      const d = await boardRead.getDrop(i);
      const state = dropState(d, now);
      let claimed = false;
      if (account) claimed = await boardRead.hasClaimed(i, account);
      const quota =
        d.maxClaims > 0 ? `${d.claimCount} / ${d.maxClaims} claimed` : `${d.claimCount} claimed (no cap)`;
      let btn;
      if (!account) btn = `<button disabled>Connect wallet to claim</button>`;
      else if (claimed) btn = `<button disabled>Claimed ✓</button>`;
      else if (!isHolder) btn = `<button disabled>Agent ID required</button>`;
      else if (state === "live") btn = `<button data-claim="${i}">Claim badge</button>`;
      else btn = `<button disabled>${state[0].toUpperCase() + state.slice(1)}</button>`;
      cards.push(
        `<article class="card"><h3>${esc(d.name)}</h3>` +
          `<p class="badge-state state-${state}">${state.toUpperCase()}</p>` +
          `<p>${quota}</p><p class="muted">${fmtWindow(d)}</p>${btn}</article>`
      );
    }
    el.innerHTML = cards.join("");
    el.querySelectorAll("[data-claim]").forEach((b) =>
      b.addEventListener("click", () => doClaim(Number(b.dataset.claim), b))
    );
  } catch (e) {
    el.innerHTML = '<p class="muted">Drops are not live yet (contract not deployed or unreachable).</p>';
  }
}

async function doClaim(dropId, btn) {
  try {
    btn.disabled = true;
    btn.textContent = "Confirm in your wallet…";
    const board = new ethers.Contract(CFG.boardAddress, BOARD_ABI, signer);
    const tx = await board.claim(dropId);
    btn.textContent = "Claiming…";
    await tx.wait();
    btn.textContent = "Claimed ✓";
    await refreshIdentity();
    await renderBadges();
    await renderLeaderboard();
  } catch (e) {
    btn.disabled = false;
    btn.textContent = "Claim badge";
    alert("Claim failed: " + (e.shortMessage || e.message || e));
  }
}

async function scanClaimedEvents(filterClaimer) {
  const latest = await readProvider.getBlockNumber();
  const events = [];
  for (let from = CFG.scanFromBlock; from <= latest; from += CFG.logChunkSize) {
    const to = Math.min(from + CFG.logChunkSize - 1, latest);
    const logs = await boardRead.queryFilter(
      boardRead.filters.Claimed(null, filterClaimer ?? null),
      from,
      to
    );
    events.push(...logs);
    if (to === latest) break;
  }
  return events;
}

async function renderBadges() {
  const el = $("myBadges");
  if (!account) {
    el.innerHTML = '<p class="muted">Connect your wallet to see your badges.</p>';
    return;
  }
  try {
    const n = await boardRead.balanceOf(account);
    if (n === 0n) {
      el.innerHTML = '<p class="muted">No badges yet — claim a live drop above.</p>';
      return;
    }
    const evs = await scanClaimedEvents(account);
    el.innerHTML =
      `<p>You hold <strong>${n}</strong> badge(s).</p><ul>` +
      evs.map((e) => `<li>Drop #${e.args.dropId} — badge #${e.args.tokenId} (${esc(e.args.handle)}.ai)</li>`).join("") +
      "</ul>";
  } catch {
    el.innerHTML = '<p class="muted">Could not load badges right now.</p>';
  }
}

async function renderLeaderboard() {
  const el = $("leaderboard");
  try {
    const evs = await scanClaimedEvents(null);
    const byHandle = new Map();
    for (const e of evs) byHandle.set(e.args.handle, (byHandle.get(e.args.handle) ?? 0) + 1);
    const rows = [...byHandle.entries()].sort((a, b) => b[1] - a[1]).slice(0, 20);
    if (rows.length === 0) {
      el.innerHTML = '<p class="muted">No claims yet.</p>';
      return;
    }
    el.innerHTML =
      "<ol>" + rows.map(([h, c]) => `<li>${esc(h)}.ai — ${c} badge(s)</li>`).join("") + "</ol>";
  } catch {
    el.innerHTML = '<p class="muted">Leaderboard unavailable right now.</p>';
  }
}

async function refreshIdentity() {
  const info = $("identityInfo");
  if (!account) {
    info.textContent = "Not connected";
    return;
  }
  try {
    const bal = await agentIdRead.balanceOf(account);
    isHolder = bal > 0n;
    if (isHolder) {
      const handle = await agentIdRead.handleOf(account);
      const badges = await boardRead.balanceOf(account).catch(() => 0n);
      info.textContent = `${handle}.ai · ${badges} badge(s) · ${account.slice(0, 6)}…${account.slice(-4)}`;
      $("holderGuidance").hidden = true;
    } else {
      info.textContent = `No Agent ID · ${account.slice(0, 6)}…${account.slice(-4)}`;
      $("holderGuidance").hidden = false;
    }
  } catch {
    info.textContent = account;
  }
}

$("connectBtn").addEventListener("click", async () => {
  if (!window.ethereum) {
    alert("No injected wallet found. Open this page in your wallet's dApp browser or with a wallet extension installed.");
    return;
  }
  const provider = new ethers.BrowserProvider(window.ethereum);
  const net = await provider.getNetwork();
  if (Number(net.chainId) !== CFG.chainId) {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: "0x" + CFG.chainId.toString(16) }],
    });
  }
  signer = await provider.getSigner();
  account = await signer.getAddress();
  $("connectBtn").textContent = "Connected";
  await refreshIdentity();
  await renderDrops();
  await renderBadges();
});

renderDrops();
renderLeaderboard();
