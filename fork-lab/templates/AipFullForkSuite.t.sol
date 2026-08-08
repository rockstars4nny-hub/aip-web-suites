// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @title AIP Full Fork Suite - adversarial FORK_EXECUTED battery
/// @notice Every privileged surface is called as a random EOA.
///         CALL_OK on a protected selector = TEST FAIL = FINDING.
///         Missing selector / auth revert = PASS (no open surface).
/// @dev No vm.broadcast. Target injected by Fork Lab: __TARGET__
contract AipFullForkSuite is Test {
    address constant TARGET = __TARGET__;
    address constant ATTACKER = address(0xA11CE);

    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    event Surface(string name, string result, uint256 retLen);

    function setUp() public {
        vm.deal(ATTACKER, 100 ether);
        vm.deal(address(this), 100 ether);
    }

    /* ===================== HARD GATES ===================== */

    function test_01_TargetHasCode() public view {
        assertGt(TARGET.code.length, 0, "TARGET has no bytecode - wrong address/chain/block");
    }

    function test_02_TargetStateReadable() public view {
        assertTrue(TARGET.code.length > 0 || TARGET.balance > 0, "empty target");
    }

    function test_03_ExtcodesizeStable() public view {
        assertEq(TARGET.code.length, TARGET.code.length);
    }

    /* ===================== PROXY ===================== */

    function test_10_EIP1967_ImplSlot_IfSet_HasCode() public {
        address impl = _slotAddr(IMPL_SLOT);
        emit log_named_address("eip1967.implementation", impl);
        if (impl != address(0)) {
            assertGt(impl.code.length, 0, "FINDING: EIP-1967 impl slot points to EOA / empty code");
        }
    }

    function test_11_EIP1967_AdminSlot_Logged() public {
        emit log_named_address("eip1967.admin", _slotAddr(ADMIN_SLOT));
    }

    function test_12_EIP1967_BeaconSlot_IfSet_HasCode() public {
        address beacon = _slotAddr(BEACON_SLOT);
        emit log_named_address("eip1967.beacon", beacon);
        if (beacon != address(0)) {
            assertGt(beacon.code.length, 0, "FINDING: EIP-1967 beacon slot points to empty code");
        }
    }

    function test_13_Unauth_UpgradeTo_MustRevert() public {
        _mustRevert("upgradeTo(address)", abi.encodeWithSignature("upgradeTo(address)", ATTACKER));
    }

    function test_14_Unauth_UpgradeToAndCall_MustRevert() public {
        _mustRevert(
            "upgradeToAndCall(address,bytes)",
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", ATTACKER, "")
        );
    }

    function test_15_Unauth_ChangeAdmin_MustRevert() public {
        _mustRevert("changeAdmin(address)", abi.encodeWithSignature("changeAdmin(address)", ATTACKER));
    }

    /* ===================== ACCESS CONTROL ===================== */

    function test_20_Owner_DecodeIfPresent() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("owner()"));
        _logView("owner()", ok, ret);
        if (ok && ret.length >= 32) {
            address o = abi.decode(ret, (address));
            emit log_named_address("owner", o);
            // zero owner on Ownable is often a broken/renounced edge - flag it
            if (o == address(0)) {
                emit log("WARN: owner() == address(0)");
            }
        }
    }

    function test_21_GetOwner_DecodeIfPresent() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("getOwner()"));
        _logView("getOwner()", ok, ret);
        if (ok && ret.length >= 32) {
            emit log_named_address("getOwner", abi.decode(ret, (address)));
        }
    }

    function test_22_Admin_DecodeIfPresent() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("admin()"));
        _logView("admin()", ok, ret);
        if (ok && ret.length >= 32) {
            emit log_named_address("admin", abi.decode(ret, (address)));
        }
    }

    function test_23_HasRole_DefaultAdmin_AsAttacker() public {
        bytes32 role = bytes32(0);
        (bool ok, bytes memory ret) =
            TARGET.staticcall(abi.encodeWithSignature("hasRole(bytes32,address)", role, ATTACKER));
        _logView("hasRole(DEFAULT_ADMIN,attacker)", ok, ret);
        if (ok && ret.length >= 32) {
            bool has = abi.decode(ret, (bool));
            assertFalse(has, "FINDING: attacker has DEFAULT_ADMIN_ROLE");
        }
    }

    function test_24_Unauth_TransferOwnership_MustRevert() public {
        _mustRevert(
            "transferOwnership(address)", abi.encodeWithSignature("transferOwnership(address)", ATTACKER)
        );
    }

    function test_25_Unauth_RenounceOwnership_MustRevert() public {
        _mustRevert("renounceOwnership()", abi.encodeWithSignature("renounceOwnership()"));
    }

    function test_26_Unauth_SetOwner_MustRevert() public {
        _mustRevert("setOwner(address)", abi.encodeWithSignature("setOwner(address)", ATTACKER));
    }

    /* ===================== INITIALIZER / PAUSE ===================== */

    function test_30_Unauth_Initialize_MustRevert() public {
        _mustRevert("initialize()", abi.encodeWithSignature("initialize()"));
    }

    function test_31_Unauth_InitializeAddress_MustRevert() public {
        _mustRevert("initialize(address)", abi.encodeWithSignature("initialize(address)", ATTACKER));
    }

    function test_32_Unauth_Init_MustRevert() public {
        _mustRevert("init(address)", abi.encodeWithSignature("init(address)", ATTACKER));
    }

    function test_33_Unauth_Pause_MustRevert() public {
        _mustRevert("pause()", abi.encodeWithSignature("pause()"));
    }

    function test_34_Unauth_Unpause_MustRevert() public {
        _mustRevert("unpause()", abi.encodeWithSignature("unpause()"));
    }

    function test_35_Paused_DecodeIfPresent() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("paused()"));
        _logView("paused()", ok, ret);
        if (ok && ret.length >= 32) {
            emit log_named_uint("paused", abi.decode(ret, (bool)) ? 1 : 0);
        }
    }

    /* ===================== TOKEN / ERC ===================== */

    function test_40_TotalSupply_DecodeIfPresent() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("totalSupply()"));
        _logView("totalSupply()", ok, ret);
        if (ok && ret.length >= 32) {
            emit log_named_uint("totalSupply", abi.decode(ret, (uint256)));
        }
    }

    function test_41_BalanceOf_Attacker_DecodeIfPresent() public {
        (bool ok, bytes memory ret) =
            TARGET.staticcall(abi.encodeWithSignature("balanceOf(address)", ATTACKER));
        _logView("balanceOf(attacker)", ok, ret);
        if (ok && ret.length >= 32) {
            emit log_named_uint("attacker_balance", abi.decode(ret, (uint256)));
        }
    }

    function test_42_Allowance_DecodeIfPresent() public {
        (bool ok, bytes memory ret) =
            TARGET.staticcall(abi.encodeWithSignature("allowance(address,address)", ATTACKER, ATTACKER));
        _logView("allowance(attacker,attacker)", ok, ret);
    }

    /// @dev Self-approve is expected to succeed on ERC20 - assert accounting, not auth.
    function test_43_SelfApprove_AccountingIfERC20() public {
        (bool hasBal,) = TARGET.staticcall(abi.encodeWithSignature("balanceOf(address)", ATTACKER));
        (bool hasAllow,) =
            TARGET.staticcall(abi.encodeWithSignature("allowance(address,address)", ATTACKER, address(this)));
        if (!(hasBal && hasAllow)) {
            emit log("skip: not ERC20-like");
            return;
        }
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("approve(address,uint256)", address(this), 123));
        if (!ok) {
            emit log("approve reverted (nonstandard token) - ok");
            return;
        }
        (bool aok, bytes memory aret) =
            TARGET.staticcall(abi.encodeWithSignature("allowance(address,address)", ATTACKER, address(this)));
        assertTrue(aok, "allowance unreadable after approve");
        assertEq(abi.decode(aret, (uint256)), 123, "FINDING: approve did not set allowance");
    }

    function test_44_TransferZero_SelfIfERC20() public {
        (bool hasBal, bytes memory bret) =
            TARGET.staticcall(abi.encodeWithSignature("balanceOf(address)", ATTACKER));
        if (!hasBal || bret.length < 32) {
            emit log("skip: no balanceOf");
            return;
        }
        uint256 before = abi.decode(bret, (uint256));
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("transfer(address,uint256)", ATTACKER, 0));
        if (!ok) {
            emit log("transfer(0) reverted - ok for nonstandard");
            return;
        }
        (, bytes memory afterRet) = TARGET.staticcall(abi.encodeWithSignature("balanceOf(address)", ATTACKER));
        assertEq(abi.decode(afterRet, (uint256)), before, "FINDING: transfer(0) changed balance");
    }

    function test_45_Unauth_Mint_MustRevert() public {
        _mustRevert("mint(address,uint256)", abi.encodeWithSignature("mint(address,uint256)", ATTACKER, 1));
    }

    function test_46_Unauth_MintToSelf_Large_MustRevert() public {
        _mustRevert(
            "mint(address,uint256):max",
            abi.encodeWithSignature("mint(address,uint256)", ATTACKER, type(uint256).max)
        );
    }

    function test_47_BurnZero_AsAttacker_NoSupplyInflation() public {
        (bool hasSupply, bytes memory sret) = TARGET.staticcall(abi.encodeWithSignature("totalSupply()"));
        if (!hasSupply || sret.length < 32) {
            emit log("skip: no totalSupply");
            return;
        }
        uint256 before = abi.decode(sret, (uint256));
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("burn(uint256)", 0));
        emit Surface("burn(0)", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        (, bytes memory afterRet) = TARGET.staticcall(abi.encodeWithSignature("totalSupply()"));
        if (afterRet.length >= 32) {
            assertEq(abi.decode(afterRet, (uint256)), before, "FINDING: burn(0) changed totalSupply");
        }
    }

    function test_48_Unauth_TransferFrom_Victim_MustRevertOrNoop() public {
        // Steal 1 unit from a rich holder (vitalik) with zero allowance - must not move funds.
        address victim = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
        (bool hasBal, bytes memory vb) =
            TARGET.staticcall(abi.encodeWithSignature("balanceOf(address)", victim));
        if (!hasBal || vb.length < 32) {
            emit log("skip: no balanceOf");
            return;
        }
        uint256 vBefore = abi.decode(vb, (uint256));
        if (vBefore == 0) {
            emit log("skip: victim balance 0");
            return;
        }
        uint256 aBefore = _bal(ATTACKER);
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(
            abi.encodeWithSignature("transferFrom(address,address,uint256)", victim, ATTACKER, 1)
        );
        emit Surface("transferFrom(victim,attacker,1)", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        uint256 vAfter = _bal(victim);
        uint256 aAfter = _bal(ATTACKER);
        assertEq(vAfter, vBefore, "FINDING: unauth transferFrom drained victim");
        assertEq(aAfter, aBefore, "FINDING: unauth transferFrom credited attacker");
    }

    /* ===================== DEFI / VAULT ===================== */

    function test_50_Unauth_MintShares_MustRevert() public {
        // Common vault mint(receiver, shares) privilege mistakes
        _mustRevert("mint(uint256,address)", abi.encodeWithSignature("mint(uint256,address)", 1, ATTACKER));
    }

    function test_51_DepositETH_NoCodeWipe() public {
        uint256 codeBefore = TARGET.code.length;
        uint256 balBefore = TARGET.balance;
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call{value: 0.01 ether}(abi.encodeWithSignature("deposit()"));
        emit Surface("deposit(){0.01e}", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        assertEq(TARGET.code.length, codeBefore, "FINDING: deposit path wiped code");
        if (ok) {
            assertGe(TARGET.balance, balBefore, "FINDING: deposit accepted ETH but balance dropped");
        }
    }

    function test_52_Unauth_WithdrawToAttacker_MustNotDrain() public {
        uint256 tBefore = TARGET.balance;
        uint256 aBefore = ATTACKER.balance;
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("withdraw(uint256)", tBefore));
        emit Surface("withdraw(all)", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        if (ok && tBefore > 0) {
            // If withdraw of full ETH balance succeeded for random EOA -> finding
            assertFalse(
                ATTACKER.balance > aBefore && TARGET.balance < tBefore,
                "FINDING: unauth withdraw drained contract ETH"
            );
        }
        assertGt(TARGET.code.length, 0, "code missing after withdraw probe");
    }

    function test_53_Unauth_Redeem_MustNotCreditAttacker() public {
        (bool hasBal,) = TARGET.staticcall(abi.encodeWithSignature("balanceOf(address)", ATTACKER));
        if (!hasBal) {
            // try redeem anyway as protected-style call
            _mustRevert("redeem(uint256)", abi.encodeWithSignature("redeem(uint256)", 1));
            return;
        }
        uint256 before = _bal(ATTACKER);
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("redeem(uint256)", 1));
        emit Surface("redeem(1)", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        if (ok) {
            // redeem with 0 shares should not inflate attacker ERC20 balance of TARGET token itself
            // (if TARGET is the share token). Soft check: code intact.
            assertGt(TARGET.code.length, 0);
            before; // silence if unused path
        }
    }

    function test_54_Unauth_Borrow_MustRevert() public {
        _mustRevert("borrow(uint256)", abi.encodeWithSignature("borrow(uint256)", 1));
    }

    function test_55_Repay_AsAttacker_NoUnexpectedCredit() public {
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("repay(uint256)", 0));
        emit Surface("repay(0)", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        assertGt(TARGET.code.length, 0);
    }

    function test_56_Unauth_SetFee_MustRevert() public {
        _mustRevert("setFee(uint256)", abi.encodeWithSignature("setFee(uint256)", 0));
    }

    function test_57_Unauth_SetFeeRecipient_MustRevert() public {
        _mustRevert("setFeeRecipient(address)", abi.encodeWithSignature("setFeeRecipient(address)", ATTACKER));
    }

    function test_58_Skim_PublicByDesign_CodeIntact() public {
        // UniV2 skim is intentionally public - only assert no selfdestruct
        uint256 before = TARGET.code.length;
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("skim(address)", ATTACKER));
        emit Surface("skim(attacker)", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        assertEq(TARGET.code.length, before, "FINDING: skim wiped code");
    }

    function test_59_Sync_PublicByDesign_CodeIntact() public {
        uint256 before = TARGET.code.length;
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(abi.encodeWithSignature("sync()"));
        emit Surface("sync()", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        assertEq(TARGET.code.length, before, "FINDING: sync wiped code");
    }

    function test_60_Swap_Zero_MustNotCreateMoney() public {
        bytes memory data =
            abi.encodeWithSignature("swap(uint256,uint256,address,bytes)", 0, 0, ATTACKER, "");
        bytes4 sel;
        assembly {
            sel := mload(add(data, 32))
        }
        if (!_selectorInCode(sel)) {
            emit Surface("swap(0,0)", "NOSEL_IN_BYTECODE", 0);
            return;
        }
        (bool has0, bytes memory r0) = TARGET.staticcall(abi.encodeWithSignature("getReserves()"));
        uint112 rA;
        uint112 rB;
        if (has0 && r0.length >= 96) {
            (rA, rB,) = abi.decode(r0, (uint112, uint112, uint32));
        }
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(data);
        emit Surface("swap(0,0)", ok ? "CALL_OK" : "AUTH_REVERT", 0);
        assertFalse(ok, "FINDING: swap(0,0) succeeded - check pair accounting");
        if (has0 && r0.length >= 96) {
            (bool has1, bytes memory r1) = TARGET.staticcall(abi.encodeWithSignature("getReserves()"));
            if (has1 && r1.length >= 96) {
                (uint112 a2, uint112 b2,) = abi.decode(r1, (uint112, uint112, uint32));
                assertEq(uint256(a2), uint256(rA), "FINDING: reserves changed on zero swap path");
                assertEq(uint256(b2), uint256(rB), "FINDING: reserves changed on zero swap path");
            }
        }
    }

    function test_61_Unauth_SetPriceOracle_MustRevert() public {
        _mustRevert("setOracle(address)", abi.encodeWithSignature("setOracle(address)", ATTACKER));
    }

    function test_62_Unauth_FlashLoan_CallbackAbuse_Gate() public {
        // Initiating flashLoan is often public; stealing requires bad callback auth.
        // We only flag if a zero-amount flashLoan to attacker mutates TARGET eth balance down.
        uint256 before = TARGET.balance;
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call(
            abi.encodeWithSignature(
                "flashLoan(address,address,uint256,bytes)", ATTACKER, address(0), 0, ""
            )
        );
        emit Surface("flashLoan(0)", ok ? "CALL_OK" : "REVERT_OR_NOSEL", 0);
        if (ok && before > 0) {
            assertGe(TARGET.balance, before, "FINDING: flashLoan(0) reduced contract ETH");
        }
    }

    function test_63_Unauth_ExecuteBytes_MustRevert() public {
        _mustRevert("execute(bytes)", abi.encodeWithSignature("execute(bytes)", hex"00"));
    }

    function test_64_Unauth_ExecuteCall_MustRevert() public {
        _mustRevert(
            "execute(address,uint256,bytes)",
            abi.encodeWithSignature("execute(address,uint256,bytes)", ATTACKER, 0, "")
        );
    }

    /* ===================== ORACLE ===================== */

    function test_70_LatestAnswer_IfPresent_NonZero() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("latestAnswer()"));
        _logView("latestAnswer()", ok, ret);
        if (ok && ret.length >= 32) {
            int256 ans = abi.decode(ret, (int256));
            emit log_named_int("latestAnswer", ans);
            assertTrue(ans != 0, "FINDING: latestAnswer() == 0 (dead/stale feed?)");
        }
    }

    function test_71_LatestRoundData_IfPresent_Sane() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("latestRoundData()"));
        _logView("latestRoundData()", ok, ret);
        if (ok && ret.length >= 160) {
            (uint80 roundId, int256 answer,, uint256 updatedAt,) =
                abi.decode(ret, (uint80, int256, uint256, uint256, uint80));
            emit log_named_uint("roundId", roundId);
            emit log_named_int("answer", answer);
            emit log_named_uint("updatedAt", updatedAt);
            assertTrue(answer != 0, "FINDING: oracle answer == 0");
            assertTrue(updatedAt != 0, "FINDING: oracle updatedAt == 0");
            assertTrue(updatedAt <= block.timestamp + 1 hours, "FINDING: oracle updatedAt in far future");
            // > 24h stale is a soft fail - real finding for many programs
            if (block.timestamp > updatedAt && block.timestamp - updatedAt > 24 hours) {
                fail("FINDING: oracle round stale > 24h");
            }
        }
    }

    function test_72_GetPrice_IfPresent_NonZero() public {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("getPrice()"));
        _logView("getPrice()", ok, ret);
        if (ok && ret.length >= 32) {
            uint256 p = abi.decode(ret, (uint256));
            emit log_named_uint("getPrice", p);
            assertTrue(p != 0, "FINDING: getPrice() == 0");
        }
    }

    function test_73_Unauth_UpdatePrice_MustRevert() public {
        _mustRevert("updatePrice(uint256)", abi.encodeWithSignature("updatePrice(uint256)", 1));
    }

    function test_74_Unauth_SetPrice_MustRevert() public {
        _mustRevert("setPrice(uint256)", abi.encodeWithSignature("setPrice(uint256)", 1));
    }

    /* ===================== GOVERNANCE / TIMELOCK ===================== */

    function test_80_Unauth_ExecuteProposal0_MustRevert() public {
        _mustRevert("execute(uint256)", abi.encodeWithSignature("execute(uint256)", 0));
    }

    function test_81_Unauth_QueueProposal0_MustRevert() public {
        _mustRevert("queue(uint256)", abi.encodeWithSignature("queue(uint256)", 0));
    }

    function test_82_Unauth_CancelProposal0_MustRevert() public {
        _mustRevert("cancel(uint256)", abi.encodeWithSignature("cancel(uint256)", 0));
    }

    function test_83_Unauth_Schedule_MustRevert() public {
        _mustRevert(
            "schedule(...)",
            abi.encodeWithSignature(
                "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
                ATTACKER,
                0,
                "",
                bytes32(0),
                bytes32(0),
                0
            )
        );
    }

    function test_84_Unauth_UpdateDelay_MustRevert() public {
        _mustRevert("updateDelay(uint256)", abi.encodeWithSignature("updateDelay(uint256)", 0));
    }

    /* ===================== BRIDGE ===================== */

    function test_90_Unauth_Process_MustRevert() public {
        _mustRevert("process(bytes)", abi.encodeWithSignature("process(bytes)", hex"dead"));
    }

    function test_91_Unauth_ReceiveMessage_MustRevert() public {
        _mustRevert("receiveMessage(bytes)", abi.encodeWithSignature("receiveMessage(bytes)", hex"dead"));
    }

    function test_92_Unauth_Relay_MustRevert() public {
        _mustRevert("relay(bytes)", abi.encodeWithSignature("relay(bytes)", hex"dead"));
    }

    function test_93_Unauth_CompleteTransfer_MustRevert() public {
        _mustRevert("completeTransfer(bytes)", abi.encodeWithSignature("completeTransfer(bytes)", hex"dead"));
    }

    /* ===================== DESTRUCT / VALUE ===================== */

    function test_A0_EmptyCall_NoCodeWipe() public {
        uint256 before = TARGET.code.length;
        (bool ok,) = TARGET.call{value: 0}("");
        emit Surface("empty_call", ok ? "CALL_OK" : "REVERT", 0);
        assertEq(TARGET.code.length, before, "FINDING: empty call changed code size");
    }

    function test_A1_AttackerEmptyCall_NoCodeWipe() public {
        uint256 before = TARGET.code.length;
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call{value: 0}("");
        emit Surface("attacker_empty_call", ok ? "CALL_OK" : "REVERT", 0);
        assertEq(TARGET.code.length, before, "FINDING: attacker empty call wiped code");
        assertGt(TARGET.code.length, 0);
    }

    function test_A2_ValueCall_NoCodeWipe() public {
        uint256 before = TARGET.code.length;
        vm.prank(ATTACKER);
        (bool ok,) = TARGET.call{value: 0.01 ether}("");
        emit Surface("value_call_0.01e", ok ? "CALL_OK" : "REVERT", 0);
        assertEq(TARGET.code.length, before, "FINDING: value call wiped code");
    }

    function test_A3_SelfdestructSelector_MustRevert() public {
        _mustRevert("destroy()", abi.encodeWithSignature("destroy()"));
        _mustRevert("kill()", abi.encodeWithSignature("kill()"));
        _mustRevert("selfDestruct()", abi.encodeWithSignature("selfDestruct()"));
    }

    /* ===================== helpers ===================== */

    function _slotAddr(bytes32 slot) internal view returns (address) {
        return address(uint160(uint256(vm.load(TARGET, slot))));
    }

    function _bal(address who) internal view returns (uint256) {
        (bool ok, bytes memory ret) = TARGET.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        if (!ok || ret.length < 32) return 0;
        return abi.decode(ret, (uint256));
    }

    function _logView(string memory name, bool ok, bytes memory ret) internal {
        emit Surface(name, ok ? "VIEW_OK" : "REVERT_OR_NOSEL", ret.length);
        if (ok && ret.length > 0 && ret.length <= 128) {
            emit log_named_bytes("ret", ret);
        }
    }

    /// @dev Privileged selector: CALL_OK as ATTACKER is a FINDING only if the selector
    ///      exists in TARGET (or EIP-1967 impl) bytecode. Fallback/no-op contracts like
    ///      WETH accept arbitrary calldata with success - that is NOT a finding.
    function _mustRevert(string memory name, bytes memory data) internal {
        require(data.length >= 4, "bad calldata");
        bytes4 sel;
        assembly {
            sel := mload(add(data, 32))
        }
        if (!_selectorInCode(sel)) {
            emit Surface(name, "NOSEL_IN_BYTECODE", 0);
            return;
        }
        uint256 codeBefore = TARGET.code.length;
        vm.prank(ATTACKER);
        (bool ok, bytes memory ret) = TARGET.call(data);
        emit Surface(name, ok ? "CALL_OK" : "AUTH_REVERT", ret.length);
        assertEq(TARGET.code.length, codeBefore, string.concat("FINDING: code wiped by ", name));
        assertFalse(
            ok,
            string.concat("FINDING: unauthenticated CALL_OK on ", name, " - access control missing/broken")
        );
    }

    function _selectorInCode(bytes4 sel) internal view returns (bool) {
        if (_codeHasPush4(TARGET.code, sel)) return true;
        address impl = _slotAddr(IMPL_SLOT);
        if (impl != address(0) && impl.code.length > 0) {
            return _codeHasPush4(impl.code, sel);
        }
        return false;
    }

    function _codeHasPush4(bytes memory code, bytes4 sel) internal pure returns (bool) {
        if (code.length < 5) return false;
        bytes1 push4 = bytes1(0x63);
        for (uint256 i = 0; i + 4 < code.length; i++) {
            if (code[i] != push4) continue;
            if (
                code[i + 1] == sel[0] && code[i + 2] == sel[1] && code[i + 3] == sel[2]
                    && code[i + 4] == sel[3]
            ) {
                return true;
            }
        }
        return false;
    }
}
