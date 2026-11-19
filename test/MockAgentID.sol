// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Test-only mock of the official Agent ID contract. In tests its
///         runtime code is etched onto the real Agent ID address
///         (0x60b9262456de011f7d15a54cdd8c48baaa8b022f) so AgentDropBoard's
///         compile-time constant gate is exercised exactly as on mainnet.
contract MockAgentID {
    mapping(address => uint256) private _balances;
    mapping(address => string) private _handles;

    function setHolder(address account, string calldata handle) external {
        _balances[account] = 1;
        _handles[account] = handle;
    }

    function setBalance(address account, uint256 value) external {
        _balances[account] = value;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function handleOf(address account) external view returns (string memory) {
        return _handles[account];
    }
}
