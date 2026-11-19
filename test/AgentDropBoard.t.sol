// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentDropBoard} from "../src/AgentDropBoard.sol";
import {MockAgentID} from "./MockAgentID.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AgentDropBoardTest is Test {
    address internal constant AGENT_ID_ADDR = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address internal constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    // Canonical Deterministic Deployment Proxy runtime bytecode, fetched from
    // BSC mainnet via eth_getCode on 2026-11-19 (identical on BSC testnet).
    bytes internal constant PROXY_RUNTIME =
        hex"7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3";

    uint64 internal constant T0 = 1_800_000_000;

    AgentDropBoard internal board;
    MockAgentID internal agentId; // interface onto the etched mock at AGENT_ID_ADDR

    address internal owner = address(0x0B0B);
    address internal kamala = 0xD0C84A723eD8536E407DA23f2ccF1d64F3E318CA; // real Agent ID holder on mainnet
    address internal holder2 = address(0xBEEF);
    address internal nonHolder = address(0xCAFE);
    address internal stranger = address(0xD00D);

    function setUp() public {
        vm.warp(T0);
        // Etch the mock Agent ID code onto the REAL Agent ID address so the
        // board's compile-time constant gate is exercised exactly as mainnet.
        MockAgentID mock = new MockAgentID();
        vm.etch(AGENT_ID_ADDR, address(mock).code);
        agentId = MockAgentID(AGENT_ID_ADDR);
        agentId.setHolder(kamala, "kamala");
        agentId.setHolder(holder2, "holdertwo");

        board = new AgentDropBoard(owner);
    }

    function _createLiveDrop(uint32 maxClaims) internal returns (uint256 id) {
        vm.prank(owner);
        id = board.createDrop("Genesis", "ipfs://agentdrop/genesis.json", T0 - 100, T0 + 10_000, maxClaims);
    }

    // ------------------------------------------------------------ gate & claim

    function testGatePointsAtOfficialAgentID() public view {
        assertEq(address(board.AGENT_ID()), AGENT_ID_ADDR);
    }

    function testNonHolderCannotClaim() public {
        uint256 id = _createLiveDrop(0);
        vm.prank(nonHolder);
        vm.expectRevert(AgentDropBoard.AgentIDRequired.selector);
        board.claim(id);
    }

    function testHolderClaimsOnce() public {
        uint256 id = _createLiveDrop(0);
        vm.expectEmit(true, true, true, true, address(board));
        emit AgentDropBoard.Claimed(id, kamala, 1, "kamala");
        vm.prank(kamala);
        board.claim(id);

        assertEq(board.ownerOf(1), kamala);
        assertEq(board.balanceOf(kamala), 1);
        assertTrue(board.hasClaimed(id, kamala));
        assertEq(board.totalBadges(), 1);
        AgentDropBoard.Drop memory d = board.getDrop(id);
        assertEq(d.claimCount, 1);
        assertEq(board.tokenURI(1), "ipfs://agentdrop/genesis.json");
    }

    function testSecondClaimReverts() public {
        uint256 id = _createLiveDrop(0);
        vm.prank(kamala);
        board.claim(id);
        vm.prank(kamala);
        vm.expectRevert(AgentDropBoard.AlreadyClaimed.selector);
        board.claim(id);
    }

    function testClaimBeforeStartReverts() public {
        vm.prank(owner);
        uint256 id = board.createDrop("Future", "ipfs://x", T0 + 1_000, T0 + 2_000, 0);
        vm.prank(kamala);
        vm.expectRevert(AgentDropBoard.DropNotStarted.selector);
        board.claim(id);
    }

    function testClaimAfterEndReverts() public {
        uint256 id = _createLiveDrop(0);
        vm.warp(T0 + 10_001);
        vm.prank(kamala);
        vm.expectRevert(AgentDropBoard.DropEnded.selector);
        board.claim(id);
    }

    function testClaimAtExactEndSucceeds() public {
        uint256 id = _createLiveDrop(0);
        vm.warp(T0 + 10_000); // window end is inclusive per spec (start <= t <= end)
        vm.prank(kamala);
        board.claim(id);
        assertTrue(board.hasClaimed(id, kamala));
    }

    function testClaimInactiveDropReverts() public {
        uint256 id = _createLiveDrop(0);
        vm.prank(owner);
        board.setDropActive(id, false);
        vm.prank(kamala);
        vm.expectRevert(AgentDropBoard.DropNotActive.selector);
        board.claim(id);
    }

    function testClaimSoldOutReverts() public {
        uint256 id = _createLiveDrop(1);
        vm.prank(kamala);
        board.claim(id);
        vm.prank(holder2);
        vm.expectRevert(AgentDropBoard.DropSoldOut.selector);
        board.claim(id);
    }

    function testClaimNonexistentDropReverts() public {
        vm.prank(kamala);
        vm.expectRevert(AgentDropBoard.DropDoesNotExist.selector);
        board.claim(99);
    }

    function testHolderCanClaimAcrossDifferentDrops() public {
        uint256 a = _createLiveDrop(0);
        vm.prank(owner);
        uint256 b = board.createDrop("Second", "ipfs://agentdrop/second.json", T0 - 100, T0 + 10_000, 0);
        vm.prank(kamala);
        board.claim(a);
        vm.prank(kamala);
        board.claim(b);
        assertEq(board.balanceOf(kamala), 2);
        assertEq(board.badgeDrop(1), a);
        assertEq(board.badgeDrop(2), b);
        assertEq(board.tokenURI(2), "ipfs://agentdrop/second.json");
    }

    // --------------------------------------------------------------- soulbound

    function testSoulboundTransferFromReverts() public {
        uint256 id = _createLiveDrop(0);
        vm.prank(kamala);
        board.claim(id);
        vm.prank(kamala);
        vm.expectRevert(AgentDropBoard.Soulbound.selector);
        board.transferFrom(kamala, holder2, 1);
    }

    function testSoulboundSafeTransferFromReverts() public {
        uint256 id = _createLiveDrop(0);
        vm.prank(kamala);
        board.claim(id);
        vm.prank(kamala);
        vm.expectRevert(AgentDropBoard.Soulbound.selector);
        board.safeTransferFrom(kamala, holder2, 1);
    }

    function testSoulboundEvenOwnerCannotMoveBadge() public {
        uint256 id = _createLiveDrop(0);
        vm.prank(kamala);
        board.claim(id);
        // Even with the holder's approval, the transfer path itself is blocked.
        vm.prank(kamala);
        board.approve(owner, 1);
        vm.prank(owner);
        vm.expectRevert(AgentDropBoard.Soulbound.selector);
        board.transferFrom(kamala, owner, 1);
    }

    // ------------------------------------------------------- owner power limits

    function testOwnerHasNoMintPathForOthers() public {
        uint256 id = _createLiveDrop(0);
        // Owner is not an Agent ID holder in this setup: claim() is self-only,
        // there is no mint-for-other function, so the owner simply reverts.
        vm.prank(owner);
        vm.expectRevert(AgentDropBoard.AgentIDRequired.selector);
        board.claim(id);
        assertEq(board.totalBadges(), 0);
    }

    function testOwnerCannotWeakenGate() public {
        uint256 id = _createLiveDrop(0);
        // Exercise every owner power; the gate must be untouched afterwards.
        vm.startPrank(owner);
        board.setDropActive(id, false);
        board.setDropActive(id, true);
        board.setDropWindow(id, T0 - 50, T0 + 5_000);
        vm.stopPrank();
        assertEq(address(board.AGENT_ID()), AGENT_ID_ADDR);
        vm.prank(nonHolder);
        vm.expectRevert(AgentDropBoard.AgentIDRequired.selector);
        board.claim(id);
    }

    function testContractRejectsNativeFunds() public {
        (bool ok,) = address(board).call{value: 1 ether}("");
        assertFalse(ok, "contract must reject plain BNB transfers");
        assertEq(address(board).balance, 0);
    }

    function testAdminFunctionsAreOwnerOnly() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        board.createDrop("X", "ipfs://x", T0, T0 + 10, 0);

        uint256 id = _createLiveDrop(0);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        board.setDropActive(id, false);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        board.setDropWindow(id, T0, T0 + 10);
    }

    function testCreateDropValidation() public {
        vm.startPrank(owner);
        vm.expectRevert(AgentDropBoard.InvalidWindow.selector);
        board.createDrop("Bad", "ipfs://x", T0 + 10, T0 + 10, 0);

        string memory longName = new string(65);
        vm.expectRevert(AgentDropBoard.NameTooLong.selector);
        board.createDrop(longName, "ipfs://x", T0, T0 + 10, 0);

        string memory longUri = new string(257);
        vm.expectRevert(AgentDropBoard.UriTooLong.selector);
        board.createDrop("Ok", longUri, T0, T0 + 10, 0);
        vm.stopPrank();
    }

    function testDropCreatedEvent() public {
        vm.expectEmit(true, false, false, true, address(board));
        emit AgentDropBoard.DropCreated(0, "Genesis", T0 - 100, T0 + 10_000, 0);
        _createLiveDrop(0);
    }

    // --------------------------------------------------------------------- fuzz

    function testFuzzCapNeverExceeded(uint8 capSeed, uint8 extraHolders) public {
        uint32 cap = uint32(capSeed) + 1; // 1..256
        uint256 id = _createLiveDrop(cap);
        uint256 attempts = uint256(cap) + (uint256(extraHolders) % 8) + 1;
        for (uint256 i = 0; i < attempts; i++) {
            address h = address(uint160(0x10000 + i));
            agentId.setHolder(h, "fuzz");
            vm.prank(h);
            try board.claim(id) {} catch {}
        }
        AgentDropBoard.Drop memory d = board.getDrop(id);
        assertEq(d.claimCount, cap);
        assertEq(board.totalBadges(), cap);
    }

    // ------------------------------------------- CREATE2 proxy deployment path
    // Proves the exact mainnet deployment route: baw contract-call -> canonical
    // Deterministic Deployment Proxy -> CREATE2. The board's owner must be the
    // address baked into the constructor args (the agent wallet), NOT the proxy.

    function testDeployViaDeterministicProxy() public {
        vm.etch(CREATE2_PROXY, PROXY_RUNTIME);

        bytes32 salt = keccak256("AgentDropBoard-v1");
        bytes memory initCode = abi.encodePacked(type(AgentDropBoard).creationCode, abi.encode(owner));
        address expected = address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", CREATE2_PROXY, salt, keccak256(initCode))))));

        (bool ok,) = CREATE2_PROXY.call(abi.encodePacked(salt, initCode));
        assertTrue(ok, "proxy call failed");
        assertGt(expected.code.length, 0, "no code at precomputed CREATE2 address");

        AgentDropBoard deployed = AgentDropBoard(expected);
        assertEq(deployed.owner(), owner, "owner must be constructor arg, not the proxy");
        assertEq(address(deployed.AGENT_ID()), AGENT_ID_ADDR);

        // The proxy-deployed board is fully functional.
        vm.prank(owner);
        uint256 id = deployed.createDrop("Genesis", "ipfs://agentdrop/genesis.json", T0 - 100, T0 + 10_000, 0);
        vm.prank(kamala);
        deployed.claim(id);
        assertEq(deployed.ownerOf(1), kamala);
    }
}
