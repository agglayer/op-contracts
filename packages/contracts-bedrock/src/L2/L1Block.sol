// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ISemver } from "src/universal/interfaces/ISemver.sol";
import { Constants } from "src/libraries/Constants.sol";
import { GasPayingToken, IGasToken } from "src/libraries/GasPayingToken.sol";
import { NotDepositor } from "src/libraries/L1BlockErrors.sol";

/// @custom:proxied true
/// @custom:predeploy 0x4200000000000000000000000000000000000015
/// @title L1Block
/// @notice The L1Block predeploy gives users access to information about the last known L1 block.
///         Values within this contract are updated once per epoch (every L1 block) and can only be
///         set by the "depositor" account, a special system address. Depositor account transactions
///         are created by the protocol whenever we move to a new epoch.
contract L1Block is ISemver, IGasToken {
    /// @notice Event emitted when the gas paying token is set.
    event GasPayingTokenSet(address indexed token, uint8 indexed decimals, bytes32 name, bytes32 symbol);

    /// @notice Address of the special depositor account.
    function DEPOSITOR_ACCOUNT() public pure returns (address addr_) {
        addr_ = Constants.DEPOSITOR_ACCOUNT;
    }

    /// @notice The latest L1 block number known by the L2 system.
    uint64 public number;

    /// @notice The latest L1 timestamp known by the L2 system.
    uint64 public timestamp;

    /// @notice The latest L1 base fee.
    uint256 public basefee;

    /// @notice The latest L1 blockhash.
    bytes32 public hash;

    /// @notice The number of L2 blocks in the same epoch.
    uint64 public sequenceNumber;

    /// @notice The scalar value applied to the L1 blob base fee portion of the blob-capable L1 cost func.
    uint32 public blobBaseFeeScalar;

    /// @notice The scalar value applied to the L1 base fee portion of the blob-capable L1 cost func.
    uint32 public baseFeeScalar;

    /// @notice The versioned hash to authenticate the batcher by.
    bytes32 public batcherHash;

    /// @notice The overhead value applied to the L1 portion of the transaction fee.
    /// @custom:legacy
    uint256 public l1FeeOverhead;

    /// @notice The scalar value applied to the L1 portion of the transaction fee.
    /// @custom:legacy
    uint256 public l1FeeScalar;

    /// @notice The latest L1 blob base fee.
    uint256 public blobBaseFee;

    /// @custom:semver 1.5.1-beta.3
    function version() public pure virtual returns (string memory) {
        return "1.5.1-beta.3";
    }

    /// @notice Returns the gas paying token, its decimals, name and symbol.
    ///         If nothing is set in state, then it means ether is used.
    function gasPayingToken() public view returns (address addr_, uint8 decimals_) {
        (addr_, decimals_) = GasPayingToken.getToken();
    }

    /// @notice Returns the gas paying token name.
    ///         If nothing is set in state, then it means ether is used.
    function gasPayingTokenName() public view returns (string memory name_) {
        name_ = GasPayingToken.getName();
    }

    /// @notice Returns the gas paying token symbol.
    ///         If nothing is set in state, then it means ether is used.
    function gasPayingTokenSymbol() public view returns (string memory symbol_) {
        symbol_ = GasPayingToken.getSymbol();
    }

    /// @notice Getter for custom gas token paying networks. Returns true if the
    ///         network uses a custom gas token.
    function isCustomGasToken() public view returns (bool) {
        (address token,) = gasPayingToken();
        return token != Constants.ETHER;
    }

    /// @custom:legacy
    /// @notice Updates the L1 block values.
    /// @param _number         L1 blocknumber.
    /// @param _timestamp      L1 timestamp.
    /// @param _basefee        L1 basefee.
    /// @param _hash           L1 blockhash.
    /// @param _sequenceNumber Number of L2 blocks since epoch start.
    /// @param _batcherHash    Versioned hash to authenticate batcher by.
    /// @param _l1FeeOverhead  L1 fee overhead.
    /// @param _l1FeeScalar    L1 fee scalar.
    function setL1BlockValues(
        uint64 _number,
        uint64 _timestamp,
        uint256 _basefee,
        bytes32 _hash,
        uint64 _sequenceNumber,
        bytes32 _batcherHash,
        uint256 _l1FeeOverhead,
        uint256 _l1FeeScalar
    )
        external
    {
        require(msg.sender == DEPOSITOR_ACCOUNT(), "L1Block: only the depositor account can set L1 block values");

        number = _number;
        timestamp = _timestamp;
        basefee = _basefee;
        hash = _hash;
        sequenceNumber = _sequenceNumber;
        batcherHash = _batcherHash;
        l1FeeOverhead = _l1FeeOverhead;
        l1FeeScalar = _l1FeeScalar;
    }

    /// @notice Updates the L1 block values for an Ecotone upgraded chain.
    /// Params are packed and passed in as raw msg.data instead of ABI to reduce calldata size.
    /// Params are expected to be in the following order:
    ///   1. _baseFeeScalar      L1 base fee scalar
    ///   2. _blobBaseFeeScalar  L1 blob base fee scalar
    ///   3. _sequenceNumber     Number of L2 blocks since epoch start.
    ///   4. _timestamp          L1 timestamp.
    ///   5. _number             L1 blocknumber.
    ///   6. _basefee            L1 base fee.
    ///   7. _blobBaseFee        L1 blob base fee.
    ///   8. _hash               L1 blockhash.
    ///   9. _batcherHash        Versioned hash to authenticate batcher by.
    function setL1BlockValuesEcotone() public {
        _setL1BlockValuesEcotone();
    }

    /// @notice Updates the L1 block values for an Ecotone upgraded chain (inline assembly).
    /// Scales L1 fee scalars into CGT terms using a RAY (1e27) factor before storing.
    /// Preserves the original sstore pattern for the packed slot.
    function _setL1BlockValuesEcotone() internal {
        address depositor = DEPOSITOR_ACCOUNT();
        assembly {
            // Revert if the caller is not the depositor account.
            if xor(caller(), depositor) {
                // 0x3cc50b45 is the 4-byte selector of "NotDepositor()"
                mstore(0x00, 0x3cc50b45)
                revert(0x1C, 0x04) // return the stored 4-byte selector
            }

            // ------------------------------------------------------------
            // Calldata layout (starting right after the 4-byte selector):
            // word @ +4  : [ baseFeeScalar(4) | blobBaseFeeScalar(4) | sequenceNumber(8) | timestamp(8) | number(8) ]
            // word @ +36 : basefee (uint256)
            // word @ +68 : blobBaseFee (uint256)
            // word @ +100: hash (bytes32)
            // word @ +132: batcherHash (bytes32)
            // ------------------------------------------------------------

            // Load the packed first word
            let w0 := calldataload(4)

            // Extract fields from w0
            let baseFeeScalarRaw      := shr(224, w0)                          // uint32
            let blobBaseFeeScalarRaw  := and(shr(192, w0), 0xffffffff)         // uint32
            let sequenceNumberVal     := and(shr(128, w0), 0xffffffffffffffff) // uint64
            let timestampVal          := and(shr(64,  w0), 0xffffffffffffffff) // uint64
            let numberVal             := and(        w0,  0xffffffffffffffff)  // uint64

            // Load remaining words
            let basefeeVal            := calldataload(36)   // uint256
            let blobBaseFeeVal        := calldataload(68)   // uint256
            let hashVal               := calldataload(100)  // bytes32
            let batcherHashVal        := calldataload(132)  // bytes32

            // -------------------------------
            // Read CGT/ETH rate (RAY, 1e27)
            // -------------------------------
            let rate := sload(cgtPerEthRay.slot)
            // RAY = 1e27
            let RAY := 1000000000000000000000000000

            // Scale baseFeeScalar and blobBaseFeeScalar (uint32) by rate, clamp to uint32 max
            // scaled = min( (raw * rate) / RAY, 0xffffffff )
            let scaledBase := div(mul(baseFeeScalarRaw, rate), RAY)
            if gt(scaledBase, 0xffffffff) { scaledBase := 0xffffffff }

            let scaledBlob := div(mul(blobBaseFeeScalarRaw, rate), RAY)
            if gt(scaledBlob, 0xffffffff) { scaledBlob := 0xffffffff }

            // ------------------------------------------------------------
            // Store to state preserving original sstore pattern:
            // 1) sequenceNumber.slot packs (low 16 bytes):
            //    [ baseFeeScalar(uint32) | blobBaseFeeScalar(uint32) | sequenceNumber(uint64) ]
            // ------------------------------------------------------------
            let packSeqScalars := or(or(shl(96, scaledBase), shl(64, scaledBlob)), sequenceNumberVal)
            sstore(sequenceNumber.slot, packSeqScalars)

            // 2) number.slot packs (low 16 bytes):
            //    [ timestamp(uint64) | number(uint64) ]
            let packNumTs := or(shl(64, timestampVal), numberVal)
            sstore(number.slot, packNumTs)

            // 3) Direct stores for remaining fields
            sstore(basefee.slot,     basefeeVal)
            sstore(blobBaseFee.slot, blobBaseFeeVal)
            sstore(hash.slot,        hashVal)
            sstore(batcherHash.slot, batcherHashVal)
        }
    }

    /// @notice Sets the gas paying token for the L2 system. Can only be called by the special
    ///         depositor account. This function is not called on every L2 block but instead
    ///         only called by specially crafted L1 deposit transactions.
    function setGasPayingToken(address _token, uint8 _decimals, bytes32 _name, bytes32 _symbol) external {
        if (msg.sender != DEPOSITOR_ACCOUNT()) revert NotDepositor();

        GasPayingToken.set({ _token: _token, _decimals: _decimals, _name: _name, _symbol: _symbol });

        emit GasPayingTokenSet({ token: _token, decimals: _decimals, name: _name, symbol: _symbol });
    }

    // ----------------------------------------------------------------
    // >>> New state (appended at the end to preserve original layout)
    // ----------------------------------------------------------------

    /// @notice CGT per 1 ETH using RAY precision (1e27). Default = 1.0 => no-op.
    uint256 public cgtPerEthRay = 1e27;

    /// @notice Optional admin allowed to update the rate besides the depositor.
    address public rateAdmin;

    event CgtPerEthRayUpdated(uint256 oldRate, uint256 newRate);
    event RateAdminUpdated(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Sets the optional rate admin. Only the depositor can set it.
    function setRateAdmin(address newAdmin) external {
        if (msg.sender != DEPOSITOR_ACCOUNT()) revert NotDepositor();
        emit RateAdminUpdated(rateAdmin, newAdmin);
        rateAdmin = newAdmin;
    }

    /// @notice Set CGT/ETH rate in RAY precision. Callable by depositor or rateAdmin.
    /// Example: 1 ETH = 5 CGT  => newRateRay = 5e27
    function setCgtPerEthRay(uint256 newRateRay) external {
        if (msg.sender != DEPOSITOR_ACCOUNT() && msg.sender != rateAdmin) revert NotDepositor();
        emit CgtPerEthRayUpdated(cgtPerEthRay, newRateRay);
        cgtPerEthRay = newRateRay;
    }
}
