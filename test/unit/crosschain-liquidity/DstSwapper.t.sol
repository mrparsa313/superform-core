// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import { Error } from "src/utils/Error.sol";

import { IStateSyncer } from "src/interfaces/IStateSyncer.sol";
import "test/utils/ProtocolActions.sol";

contract DstSwapperTest is ProtocolActions {
    address dstRefundAddress = address(444);

    function setUp() public override {
        super.setUp();
    }

    function test_token_emergency_withdraw() public {
        uint256 transferAmount = 1 * 10 ** 18; // 1 token
        address payable token = payable(getContract(ETH, "DAI"));
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));

        /// @dev admin transfers some ETH and DAI tokens to multi tx processor
        vm.selectFork(FORKS[ETH]);
        vm.startPrank(deployer);

        uint256 balanceBefore = MockERC20(token).balanceOf(dstSwapper);
        MockERC20(token).transfer(dstSwapper, transferAmount);
        uint256 balanceAfter = MockERC20(token).balanceOf(dstSwapper);
        assertEq(balanceBefore + transferAmount, balanceAfter);

        balanceBefore = MockERC20(token).balanceOf(dstSwapper);
        DstSwapper(dstSwapper).emergencyWithdrawToken(token, transferAmount);
        balanceAfter = MockERC20(token).balanceOf(dstSwapper);
        assertEq(balanceBefore - transferAmount, balanceAfter);
    }

    function test_native_token_emergency_withdraw() public {
        uint256 transferAmount = 1e18; // 1 token
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));

        /// @dev admin transfers some ETH and DAI tokens to multi tx processor
        vm.selectFork(FORKS[ETH]);
        vm.startPrank(deployer);

        uint256 balanceBefore = dstSwapper.balance;
        (bool success,) = dstSwapper.call{ value: transferAmount }("");
        if (success) {
            uint256 balanceAfter = dstSwapper.balance;
            assertEq(balanceBefore + transferAmount, balanceAfter);

            balanceBefore = dstSwapper.balance;
            DstSwapper(dstSwapper).emergencyWithdrawNativeToken(transferAmount);
            balanceAfter = dstSwapper.balance;
            assertEq(balanceBefore - transferAmount, balanceAfter);
        } else {
            revert();
        }
    }

    function test_native_token_emergency_withdrawFailure() public {
        uint256 transferAmount = 1e18; // 1 token
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));

        /// @dev admin transfers some ETH and DAI tokens to multi tx processor
        vm.selectFork(FORKS[ETH]);

        uint256 balanceBefore = dstSwapper.balance;

        vm.startPrank(deployer);
        (bool success,) = dstSwapper.call{ value: transferAmount }("");
        if (success) {
            uint256 balanceAfter = dstSwapper.balance;
            assertEq(balanceBefore + transferAmount, balanceAfter);

            SuperRBAC(getContract(ETH, "SuperRBAC")).grantRole(
                SuperRBAC(getContract(ETH, "SuperRBAC")).EMERGENCY_ADMIN_ROLE(), address(this)
            );
            vm.stopPrank();
            balanceBefore = dstSwapper.balance;
            vm.expectRevert(Error.NATIVE_TOKEN_TRANSFER_FAILURE.selector);
            DstSwapper(dstSwapper).emergencyWithdrawNativeToken(transferAmount);
            balanceAfter = dstSwapper.balance;
            assertEq(balanceBefore, balanceAfter);
        } else {
            revert();
        }
    }

    function test_failed_native_process_tx() public {
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));
        address payable coreStateRegistry = payable(getContract(ETH, "CoreStateRegistry"));

        vm.selectFork(FORKS[ETH]);
        _simulateSingleVaultExistingPayload(coreStateRegistry);
        _simulateSingleVaultExistingPayload(coreStateRegistry);

        vm.startPrank(deployer);
        address native = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        (bool success,) = payable(dstSwapper).call{ value: 1e18 }("");

        if (success) {
            DstSwapper(dstSwapper).processTx(
                1, 0, 1, _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0), 1
            );

            bytes memory txData =
                _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);

            /// @dev try with a non-existent index
            vm.expectRevert(Error.INVALID_INDEX.selector);
            DstSwapper(dstSwapper).processTx(1, 420, 1, txData, 1);

            txData = _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);

            /// @dev retry the same payload id and indices
            vm.expectRevert(Error.DST_SWAP_ALREADY_PROCESSED.selector);
            DstSwapper(dstSwapper).processTx(1, 0, 1, txData, 1);

            txData = _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);

            /// @dev no funds in multi-tx processor at this point; should revert
            vm.expectRevert(Error.FAILED_TO_EXECUTE_TXDATA_NATIVE.selector);
            DstSwapper(dstSwapper).processTx(2, 0, 1, txData, 1);
        } else {
            revert();
        }
    }

    function test_failed_non_native_process_tx() public {
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));
        address payable coreStateRegistry = payable(getContract(ETH, "CoreStateRegistry"));

        vm.selectFork(FORKS[ETH]);
        _simulateSingleVaultExistingPayload(coreStateRegistry);

        vm.startPrank(deployer);
        bytes memory txData =
            _buildLiqBridgeTxDataDstSwap(1, getContract(ETH, "WETH"), getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);
        /// @dev no funds in multi-tx processor at this point; should revert
        vm.expectRevert(Error.FAILED_TO_EXECUTE_TXDATA.selector);
        DstSwapper(dstSwapper).processTx(1, 0, 1, txData, 1);
    }

    function test_non_native_processFailedTx() public {
        address payable dstSwapper = payable(getContract(OP, "DstSwapper"));
        address payable coreStateRegistry = payable(getContract(OP, "CoreStateRegistry"));

        vm.selectFork(FORKS[OP]);
        // _simulateSingleVaultExistingPayload(coreStateRegistry);
        uint256 superformId = _simulateSingleVaultExistingPayloadOnOP(coreStateRegistry);

        vm.startPrank(deployer);
        // address native = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        address weth = getContract(OP, "WETH");

        // (bool success,) = payable(dstSwapper).call{ value: 1e18 }("");
        deal(weth, dstSwapper, 1e18);

        // if (success) {
        // console.log("BEEF", coreStateRegistry.balance);
        console.log("BEEF", IERC20(weth).balanceOf(coreStateRegistry));
        DstSwapper(dstSwapper).processFailedTx(1, superformId, weth, 1e18);
        console.log("AAAF", IERC20(weth).balanceOf(coreStateRegistry));
        // console.log("AAAF", coreStateRegistry.balance);

        /// @dev set quorum to 0 for simplicity in testing setup
        SuperRegistry(getContract(OP, "SuperRegistry")).setRequiredMessagingQuorum(ETH, 0);

        uint256[] memory finalAmounts = new uint256[](1);
        finalAmounts[0] = 1e18;
        CoreStateRegistry(coreStateRegistry).updateDepositPayload(1, finalAmounts);
        // } else {
        //     revert();
        // }

        vm.stopPrank();

        AMBs = [2, 3];
        CHAIN_0 = ETH;
        DST_CHAINS = [OP];

        /// @dev define vaults amounts and slippage for every destination chain and for every action
        TARGET_UNDERLYINGS[OP][0] = [2];
        TARGET_VAULTS[OP][0] = [0];

        /// @dev id 0 is normal 4626
        TARGET_FORM_KINDS[OP][0] = [0];

        AMOUNTS[OP][0] = [1e18];
        MAX_SLIPPAGE = 1000;
        LIQ_BRIDGES[OP][0] = [1];

        actions.push(
            TestAction({
                action: Actions.RescueFailedDeposit,
                multiVaults: false, //!!WARNING turn on or off multi vaults
                user: 0,
                testType: TestType.Pass,
                revertError: "",
                revertRole: "",
                slippage: 100, // 0% <- if we are testing a pass this must be below each maxSlippage,
                dstSwap: true,
                externalToken: 2 // 0 = DAI, 1 = USDT, 2 = WETH
             })
        );

        _rescueFailedDeposits(actions[0], 0);
    }

    function test_failed_batch_process_tx() public {
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));
        address payable coreStateRegistry = payable(getContract(ETH, "CoreStateRegistry"));

        vm.selectFork(FORKS[ETH]);
        _simulateMultiVaultExistingPayload(coreStateRegistry);
        _simulateMultiVaultExistingPayload(coreStateRegistry);

        vm.startPrank(deployer);

        address native = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        uint8[] memory bridgeId = new uint8[](2);
        bridgeId[0] = 1;
        bridgeId[1] = 1;

        address[] memory approvalToken = new address[](2);
        approvalToken[0] = native;
        approvalToken[1] = native;

        bytes[] memory txData = new bytes[](2);
        txData[0] = _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);
        txData[1] = _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        uint256[] memory indices = new uint256[](2);
        indices[0] = 2;
        indices[1] = 2;

        (bool success,) = payable(dstSwapper).call{ value: 2e18 }("");
        if (!success) revert();

        vm.expectRevert(Error.INVALID_INDEX.selector);
        DstSwapper(dstSwapper).batchProcessTx(1, indices, bridgeId, txData, indices);
        indices[0] = 0;
        indices[1] = 1;
        DstSwapper(dstSwapper).batchProcessTx(1, indices, bridgeId, txData, indices);

        /// @dev retry the same payload id and indices
        vm.expectRevert(Error.DST_SWAP_ALREADY_PROCESSED.selector);
        DstSwapper(dstSwapper).batchProcessTx(1, indices, bridgeId, txData, indices);

        /// @dev retry the same payload id and indices in reversed manner
        vm.expectRevert(Error.DST_SWAP_ALREADY_PROCESSED.selector);
        indices[0] = 1;
        indices[1] = 0;
        DstSwapper(dstSwapper).batchProcessTx(1, indices, bridgeId, txData, indices);

        /// @dev no funds in multi-tx processor at this point; should revert
        vm.expectRevert(Error.FAILED_TO_EXECUTE_TXDATA_NATIVE.selector);
        DstSwapper(dstSwapper).batchProcessTx(2, indices, bridgeId, txData, indices);
    }

    function test_failed_batch_process_tx_INVALID_PAYLOAD_STATUS() public {
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));
        address payable coreStateRegistry = payable(getContract(ETH, "CoreStateRegistry"));

        vm.selectFork(FORKS[ETH]);
        _simulateMultiVaultExistingPayload(coreStateRegistry);

        vm.startPrank(deployer);

        address native = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

        uint8[] memory bridgeId = new uint8[](2);
        bridgeId[0] = 1;
        bridgeId[1] = 1;

        address[] memory approvalToken = new address[](2);
        approvalToken[0] = native;
        approvalToken[1] = native;

        bytes[] memory txData = new bytes[](2);
        txData[0] = _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);
        txData[1] = _buildLiqBridgeTxDataDstSwap(1, native, getContract(ETH, "DAI"), dstSwapper, ETH, 1e18, 0);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;

        (bool success,) = payable(dstSwapper).call{ value: 2e18 }("");
        if (!success) revert();
        SuperRegistry(getContract(ETH, "SuperRegistry")).setRequiredMessagingQuorum(POLY, 0);

        CoreStateRegistry(coreStateRegistry).processPayload{ value: 10 ether }(1);

        vm.expectRevert(Error.INVALID_PAYLOAD_STATUS.selector);
        DstSwapper(dstSwapper).batchProcessTx(1, indices, bridgeId, txData, indices);
    }

    function test_failed_INVALID_SWAP_OUTPUT() public {
        address payable dstSwapper = payable(getContract(ETH, "DstSwapper"));
        address payable coreStateRegistry = payable(getContract(ETH, "CoreStateRegistry"));

        vm.selectFork(FORKS[ETH]);
        _simulateSingleVaultExistingPayload(coreStateRegistry);

        vm.startPrank(deployer);

        bytes memory txData =
            _buildLiqBridgeTxDataDstSwap(1, getContract(ETH, "WETH"), getContract(ETH, "DAI"), dstSwapper, ETH, 0, 0);
        /// @dev txData with amount 0 should revert
        vm.expectRevert(Error.INVALID_SWAP_OUTPUT.selector);
        DstSwapper(dstSwapper).processTx(1, 0, 1, txData, 1);
    }

    function _simulateSingleVaultExistingPayload(address payable coreStateRegistry)
        internal
        returns (uint256 superformId)
    {
        /// simulate an existing payload in csr
        address superform = getContract(ETH, string.concat("DAI", "VaultMock", "Superform", "1"));
        superformId = DataLib.packSuperform(superform, 1, ETH);

        LiqRequest memory liq;
        vm.prank(getContract(ETH, "LayerzeroImplementation"));
        CoreStateRegistry(coreStateRegistry).receivePayload(
            137,
            abi.encode(
                AMBMessage(
                    0,
                    abi.encode(InitSingleVaultData(1, 1, superformId, 1e18, 0, true, liq, dstRefundAddress, bytes("")))
                )
            )
        );
    }

    function _simulateSingleVaultExistingPayloadOnOP(address payable coreStateRegistry)
        internal
        returns (uint256 superformId)
    {
        /// simulate an existing payload in csr
        address superform = getContract(OP, string.concat("WETH", "VaultMock", "Superform", "1"));
        superformId = DataLib.packSuperform(superform, 1, OP);

        LiqRequest memory liq;
        bytes memory message = abi.encode(
            AMBMessage(
                DataLib.packTxInfo(
                    uint8(TransactionType.DEPOSIT),
                    /// @dev TransactionType
                    uint8(CallbackType.INIT),
                    0,
                    /// @dev isMultiVaults
                    1,
                    /// @dev STATE_REGISTRY_TYPE,
                    getContract(ETH, "LayerzeroImplementation"),
                    /// @dev srcSender,
                    ETH
                ),
                abi.encode(InitSingleVaultData(1, 1, superformId, 1e18, 1000, true, liq, dstRefundAddress, bytes("")))
            )
        );

        // bytes memory proof = abi.encode(
        //     AMBMessage(
        //         DataLib.packTxInfo(
        //             uint8(TransactionType.DEPOSIT),
        //             /// @dev TransactionType
        //             uint8(CallbackType.INIT),
        //             0,
        //             /// @dev isMultiVaults
        //             1,
        //             /// @dev STATE_REGISTRY_TYPE,
        //             getContract(ETH, "LayerzeroImplementation"),
        //             /// @dev srcSender,
        //             ETH
        //         ),
        //         abi.encode(
        //             keccak256(
        //                 abi.encode(
        //                     InitSingleVaultData(1, 1, superformId, 1e18, 1000, true, liq, dstRefundAddress,
        // bytes(""))
        //                 )
        //             )
        //         )
        //     )
        // );

        vm.prank(getContract(OP, "LayerzeroImplementation"));
        CoreStateRegistry(coreStateRegistry).receivePayload(1, message);
        // vm.prank(getContract(OP, "LayerzeroImplementation"));
        // CoreStateRegistry(coreStateRegistry).receivePayload(1, proof);
        // vm.prank(getContract(OP, "LayerzeroImplementation"));
        // CoreStateRegistry(coreStateRegistry).receivePayload(1, proof);
        // vm.prank(getContract(OP, "LayerzeroImplementation"));
        // CoreStateRegistry(coreStateRegistry).receivePayload(1, proof);
    }

    function _simulateMultiVaultExistingPayload(address payable coreStateRegistry) internal {
        /// simulate an existing payload in csr
        address superform = getContract(ETH, string.concat("DAI", "VaultMock", "Superform", "1"));
        uint256 superformId = DataLib.packSuperform(superform, 1, ETH);

        vm.prank(getContract(ETH, "LayerzeroImplementation"));

        uint256[] memory superformIds = new uint256[](2);
        superformIds[0] = superformId;
        superformIds[1] = superformId;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        bool[] memory hasDstSwaps = new bool[](2);
        hasDstSwaps[0] = true;
        hasDstSwaps[1] = true;

        LiqRequest[] memory liq = new LiqRequest[](2);
        CoreStateRegistry(coreStateRegistry).receivePayload(
            POLY,
            abi.encode(
                AMBMessage(
                    DataLib.packTxInfo(1, 0, 1, 1, address(420), uint64(137)),
                    abi.encode(
                        InitMultiVaultData(
                            1, 1, superformIds, amounts, new uint256[](2), hasDstSwaps, liq, dstRefundAddress, bytes("")
                        )
                    )
                )
            )
        );
    }
}
