// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice Minimal interface of the official Agent ID contract on BNB Smart Chain
///         (SPACE ID Agent ID, 0x60b9262456de011f7d15a54cdd8c48baaa8b022f).
interface IAgentID {
    function balanceOf(address account) external view returns (uint256);
    function handleOf(address account) external view returns (string memory);
}

/// @title AgentDropBoard — a free-claim board exclusively for Agent ID holders.
/// @notice Projects list time-boxed "drops". A wallet that holds an Agent ID
///         (checked on-chain against the official Agent ID contract) may claim
///         one soulbound badge per drop. The badge is bound to the claimer's
///         .ai handle, which is read on-chain at claim time and recorded in the
///         `Claimed` event.
///
///         SECURITY / OWNER-PERMISSION DISCLOSURE (public, by design):
///         - This contract NEVER takes custody of user funds. `claim` is
///           nonpayable, there is no `receive`/`fallback`, and there is no
///           withdraw function of any kind.
///         - No token approvals are ever requested from users. The only user
///           interaction is a single `claim` transaction.
///         - Badges are soulbound: every transfer or burn reverts. Badges are
///           non-transferable collectibles; no value or returns of any kind
///           are promised or implied.
///         - The owner can do exactly three things: `createDrop`,
///           `setDropActive`, and `setDropWindow` (plus standard Ownable
///           ownership transfer). The owner cannot mint badges for anyone,
///           cannot change or bypass the Agent ID gate, cannot cancel or
///           alter a claim that already happened, and cannot take anyone's
///           badge.
///         - The contract is not upgradeable, has no proxy, and no
///           selfdestruct. The Agent ID gate address is a compile-time
///           constant pointing at the official Agent ID contract.
contract AgentDropBoard is ERC721, Ownable, ReentrancyGuard {
    /// @notice The official Agent ID contract (BNB Smart Chain mainnet).
    IAgentID public constant AGENT_ID = IAgentID(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);

    error AgentIDRequired();
    error DropDoesNotExist();
    error DropNotActive();
    error DropNotStarted();
    error DropEnded();
    error AlreadyClaimed();
    error DropSoldOut();
    error Soulbound();
    error InvalidWindow();
    error NameTooLong();
    error UriTooLong();

    struct Drop {
        string name; // <= 64 bytes
        string metadataURI; // <= 256 bytes; also the tokenURI of this drop's badges
        uint64 startTime;
        uint64 endTime;
        uint32 maxClaims; // 0 = unlimited
        uint32 claimCount;
        bool active;
    }

    Drop[] public drops;
    mapping(uint256 => mapping(address => bool)) public claimed; // dropId => user => claimed
    mapping(uint256 => uint256) public badgeDrop; // badge tokenId => dropId
    uint256 public totalBadges;

    event Claimed(uint256 indexed dropId, address indexed claimer, uint256 indexed tokenId, string handle);
    event DropCreated(uint256 indexed dropId, string name, uint64 startTime, uint64 endTime, uint32 maxClaims);
    event DropActiveSet(uint256 indexed dropId, bool active);
    event DropWindowSet(uint256 indexed dropId, uint64 startTime, uint64 endTime);

    /// @param initialOwner The board owner (drop administration only, see the
    ///        disclosure above). Passed explicitly because deployment happens
    ///        through a CREATE2 proxy, where the immediate deployer would
    ///        otherwise become the owner.
    constructor(address initialOwner) ERC721("AgentDrop Badge", "ADROP") Ownable(initialOwner) {}

    // ------------------------------------------------------------------ claim

    /// @notice Claim one soulbound badge from an active drop. Caller must hold
    ///         an Agent ID. One claim per address per drop.
    function claim(uint256 dropId) external nonReentrant {
        if (dropId >= drops.length) revert DropDoesNotExist();
        Drop storage drop = drops[dropId];
        if (!drop.active) revert DropNotActive();
        if (block.timestamp < drop.startTime) revert DropNotStarted();
        if (block.timestamp > drop.endTime) revert DropEnded();
        if (claimed[dropId][msg.sender]) revert AlreadyClaimed();
        if (drop.maxClaims != 0 && drop.claimCount >= drop.maxClaims) revert DropSoldOut();
        if (AGENT_ID.balanceOf(msg.sender) == 0) revert AgentIDRequired();

        claimed[dropId][msg.sender] = true;
        drop.claimCount += 1;
        uint256 tokenId = ++totalBadges;
        badgeDrop[tokenId] = dropId;

        // Read-only call into the official Agent ID contract: bind the badge
        // to the claimer's .ai handle in the permanent event log.
        string memory handle = AGENT_ID.handleOf(msg.sender);
        _mint(msg.sender, tokenId);
        emit Claimed(dropId, msg.sender, tokenId, handle);
    }

    // ------------------------------------------------------------- owner admin

    /// @notice Register a new drop. Owner only.
    function createDrop(string calldata name_, string calldata metadataURI_, uint64 startTime, uint64 endTime, uint32 maxClaims)
        external
        onlyOwner
        returns (uint256 dropId)
    {
        if (bytes(name_).length > 64) revert NameTooLong();
        if (bytes(metadataURI_).length > 256) revert UriTooLong();
        if (startTime >= endTime) revert InvalidWindow();
        drops.push(
            Drop({
                name: name_,
                metadataURI: metadataURI_,
                startTime: startTime,
                endTime: endTime,
                maxClaims: maxClaims,
                claimCount: 0,
                active: true
            })
        );
        dropId = drops.length - 1;
        emit DropCreated(dropId, name_, startTime, endTime, maxClaims);
    }

    /// @notice Activate or deactivate a drop (e.g. a drop with bad metadata). Owner only.
    function setDropActive(uint256 dropId, bool active_) external onlyOwner {
        if (dropId >= drops.length) revert DropDoesNotExist();
        drops[dropId].active = active_;
        emit DropActiveSet(dropId, active_);
    }

    /// @notice Correct the schedule of a drop. Owner only.
    function setDropWindow(uint256 dropId, uint64 startTime, uint64 endTime) external onlyOwner {
        if (dropId >= drops.length) revert DropDoesNotExist();
        if (startTime >= endTime) revert InvalidWindow();
        drops[dropId].startTime = startTime;
        drops[dropId].endTime = endTime;
        emit DropWindowSet(dropId, startTime, endTime);
    }

    // ------------------------------------------------------------------- views

    function dropCount() external view returns (uint256) {
        return drops.length;
    }

    function getDrop(uint256 dropId) external view returns (Drop memory) {
        if (dropId >= drops.length) revert DropDoesNotExist();
        return drops[dropId];
    }

    function hasClaimed(uint256 dropId, address user) external view returns (bool) {
        return claimed[dropId][user];
    }

    /// @notice Each drop has its own metadata; a badge's tokenURI is its drop's URI.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return drops[badgeDrop[tokenId]].metadataURI;
    }

    // --------------------------------------------------------------- soulbound

    /// @dev Blocks every transfer and burn: an existing badge can never move.
    ///      Only minting (previous owner == address(0)) is allowed through.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }
}
