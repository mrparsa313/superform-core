/// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.19;

/// @title IDstSwapper
/// @author Zeropoint Labs
/// @dev handles all destination chain swaps.
/// @notice all write functions can only be accessed by superform keepers.
interface IDstSwapper {
    /*///////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct FailedSwap {
        address interimToken;
        uint256 amount;
    }

    /*///////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    /// @dev is emitted when the super registry is updated.
    event SuperRegistryUpdated(address indexed superRegistry);

    /// @dev is emitted when a dst swap transaction is processed
    event SwapProcessed(uint256 payloadId, uint256 index, uint256 bridgeId, uint256 finalAmount);

    /// @dev is emitted when a dst swap fails and intermediary tokens are sent to CoreStateRegistry for rescue
    event SwapFailed(uint256 payloadId, uint256 index, address intermediaryToken, uint256 amount);

    /// @dev would interact with liquidity bridge contract to process multi-tx transactions and move the funds into
    /// destination
    /// contract.
    /// @param payloadId_ represents the id of the payload
    /// @param index_ represents the index of the superformid in the payload
    /// @param bridgeId_ represents the id of liquidity bridge used
    /// @param txData_ represents the transaction data generated by liquidity bridge API.
    function processTx(
        uint256 payloadId_,
        uint256 index_,
        uint8 bridgeId_,
        bytes calldata txData_,
        uint256 underlyingWith0Slippage_
    )
        external;

    function processFailedTx(
        uint256 payloadId_,
        uint256 index_,
        address intermediaryToken_,
        uint256 amount_
    )
        external;

    /// @dev would interact with liquidity bridge contract to process multi-tx transactions and move the funds into
    /// destination
    /// contract.
    /// @param payloadId_ represents the array of payload ids used
    /// @param indices_ represents the index of the superformid in the payload
    /// @param bridgeIds_ represents the array of ids of liquidity bridges used
    /// @param txDatas_  represents the array of transaction data generated by liquidity bridge API
    function batchProcessTx(
        uint256 payloadId_,
        uint256[] calldata indices_,
        uint8[] calldata bridgeIds_,
        bytes[] calldata txDatas_,
        uint256[] calldata underlyingsWith0Slippage_
    )
        external;

    /// FIMXE: add natspec
    function swappedAmount(uint256 payloadId_, uint256 index_) external view returns (uint256 amount_);
    function getFailedSwap(
        uint256 payloadId_,
        uint256 superformId_
    )
        external
        view
        returns (address interimToken, uint256 amount);
}
