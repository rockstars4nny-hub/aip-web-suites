// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/// @title AIP Full Fork Suite - FORK_EXECUTED evidence battery
/// @notice Runs on every Run Fork. No vm.broadcast. Informational probes log CALL_OK / REVERT.
/// @dev Target injected by Fork Lab runner: __TARGET__ / __LABEL__
contract AipFullForkSuite is Test {
    address constant TARGET = __TARGET__;

    // EIP-1967 (keccak(eip1967.proxy.*) - 1)
    bytes32 constant IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    event Probe(string name, bool ok, uint256 retLen);

    function setUp() public {
        // Fork provided by: forge test --fork-url --fork-block-number
    }

    /* ------------- HARD GATES ------------- */

    function test_01_TargetHasCode() public view {
        assertGt(TARGET.code.length, 0, "TARGET has no bytecode on fork - wrong address/chain/block?");
    }

    function test_02_TargetStateReadable() public view {
        uint256 bal = TARGET.balance;
        uint256 codeLen = TARGET.code.length;
        assertTrue(codeLen > 0 || bal > 0, "unreadable / empty target");
        bal; // silence
    }

    function test_03_ExtcodesizeStable() public view {
        uint256 a = TARGET.code.length;
        uint256 b = TARGET.code.length;
        assertEq(a, b, "code length unstable in view context");
    }

    /* ------------- PROXY / UPGRADE SURFACE ------------- */

    function test_10_EIP1967_ImplementationSlot() public {
        bytes32 slot = vm.load(TARGET, IMPL_SLOT);
        address impl = address(uint160(uint256(slot)));
        emit log_named_address("eip1967.implementation", impl);
        emit log_named_bytes32("raw", slot);
        assertTrue(true);
    }

    function test_11_EIP1967_AdminSlot() public {
        bytes32 slot = vm.load(TARGET, ADMIN_SLOT);
        address admin = address(uint160(uint256(slot)));
        emit log_named_address("eip1967.admin", admin);
        assertTrue(true);
    }

    function test_12_EIP1967_BeaconSlot() public {
        bytes32 slot = vm.load(TARGET, BEACON_SLOT);
        address beacon = address(uint160(uint256(slot)));
        emit log_named_address("eip1967.beacon", beacon);
        assertTrue(true);
    }

    function test_13_Probe_UpgradeTo() public {
        _probe("upgradeTo(address)", abi.encodeWithSignature("upgradeTo(address)", address(this)));
    }

    function test_14_Probe_UpgradeToAndCall() public {
        _probe(
            "upgradeToAndCall(address,bytes)",
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(this), "")
        );
    }

    function test_15_Probe_ChangeAdmin() public {
        _probe("changeAdmin(address)", abi.encodeWithSignature("changeAdmin(address)", address(this)));
    }

    /* ------------- ACCESS CONTROL ------------- */

    function test_20_Probe_Owner() public {
        _probeView("owner()", abi.encodeWithSignature("owner()"));
    }

    function test_21_Probe_GetOwner() public {
        _probeView("getOwner()", abi.encodeWithSignature("getOwner()"));
    }

    function test_22_Probe_Admin() public {
        _probeView("admin()", abi.encodeWithSignature("admin()"));
    }

    function test_23_Probe_HasRole_DefaultAdmin() public {
        bytes32 defaultAdmin = 0x00;
        _probeView(
            "hasRole(DEFAULT_ADMIN)",
            abi.encodeWithSignature("hasRole(bytes32,address)", defaultAdmin, address(this))
        );
    }

    function test_24_Probe_TransferOwnership() public {
        _probe("transferOwnership(address)", abi.encodeWithSignature("transferOwnership(address)", address(this)));
    }

    function test_25_Probe_RenounceOwnership() public {
        _probe("renounceOwnership()", abi.encodeWithSignature("renounceOwnership()"));
    }

    function test_26_Probe_SetOwner() public {
        _probe("setOwner(address)", abi.encodeWithSignature("setOwner(address)", address(this)));
    }

    /* ------------- INITIALIZER / PAUSE ------------- */

    function test_30_Probe_Initialize() public {
        _probe("initialize()", abi.encodeWithSignature("initialize()"));
    }

    function test_31_Probe_Initialize_Address() public {
        _probe("initialize(address)", abi.encodeWithSignature("initialize(address)", address(this)));
    }

    function test_32_Probe_Init() public {
        _probe("init(address)", abi.encodeWithSignature("init(address)", address(this)));
    }

    function test_33_Probe_Pause() public {
        _probe("pause()", abi.encodeWithSignature("pause()"));
    }

    function test_34_Probe_Unpause() public {
        _probe("unpause()", abi.encodeWithSignature("unpause()"));
    }

    function test_35_Probe_PausedView() public {
        _probeView("paused()", abi.encodeWithSignature("paused()"));
    }

    /* ------------- TOKEN / ERC SURFACE ------------- */

    function test_40_Probe_TotalSupply() public {
        _probeView("totalSupply()", abi.encodeWithSignature("totalSupply()"));
    }

    function test_41_Probe_BalanceOf() public {
        _probeView("balanceOf(address)", abi.encodeWithSignature("balanceOf(address)", address(this)));
    }

    function test_42_Probe_Allowance() public {
        _probeView(
            "allowance(address,address)",
            abi.encodeWithSignature("allowance(address,address)", address(this), address(this))
        );
    }

    function test_43_Probe_ApproveMax() public {
        _probe("approve(address,uint256)", abi.encodeWithSignature("approve(address,uint256)", address(this), type(uint256).max));
    }

    function test_44_Probe_Transfer() public {
        _probe("transfer(address,uint256)", abi.encodeWithSignature("transfer(address,uint256)", address(this), 0));
    }

    function test_45_Probe_Mint() public {
        _probe("mint(address,uint256)", abi.encodeWithSignature("mint(address,uint256)", address(this), 1));
    }

    function test_46_Probe_Burn() public {
        _probe("burn(uint256)", abi.encodeWithSignature("burn(uint256)", 0));
    }

    function test_47_Probe_TransferFrom() public {
        _probe(
            "transferFrom(address,address,uint256)",
            abi.encodeWithSignature("transferFrom(address,address,uint256)", address(this), address(this), 0)
        );
    }

    /* ------------- DEFI / VAULT / LENDING ------------- */

    function test_50_Probe_Deposit() public {
        _probe("deposit(uint256)", abi.encodeWithSignature("deposit(uint256)", 0));
    }

    function test_51_Probe_DepositETH() public {
        (bool ok, bytes memory ret) = TARGET.call{value: 0}(abi.encodeWithSignature("deposit()"));
        emit Probe("deposit()", ok, ret.length);
        emit log_named_string("deposit()", ok ? "CALL_OK" : "REVERT_OR_NOSEL");
        assertTrue(true);
    }

    function test_52_Probe_Withdraw() public {
        _probe("withdraw(uint256)", abi.encodeWithSignature("withdraw(uint256)", 0));
    }

    function test_53_Probe_Redeem() public {
        _probe("redeem(uint256)", abi.encodeWithSignature("redeem(uint256)", 0));
    }

    function test_54_Probe_Borrow() public {
        _probe("borrow(uint256)", abi.encodeWithSignature("borrow(uint256)", 0));
    }

    function test_55_Probe_Repay() public {
        _probe("repay(uint256)", abi.encodeWithSignature("repay(uint256)", 0));
    }

    function test_56_Probe_Liquidate() public {
        _probe(
            "liquidate(address,address,uint256)",
            abi.encodeWithSignature("liquidate(address,address,uint256)", address(this), address(this), 0)
        );
    }

    function test_57_Probe_LiquidateBorrow() public {
        _probe(
            "liquidateBorrow(address,uint256,address)",
            abi.encodeWithSignature("liquidateBorrow(address,uint256,address)", address(this), 0, address(this))
        );
    }

    function test_58_Probe_Skim() public {
        _probe("skim(address)", abi.encodeWithSignature("skim(address)", address(this)));
    }

    function test_59_Probe_Sync() public {
        _probe("sync()", abi.encodeWithSignature("sync()"));
    }

    function test_60_Probe_Swap() public {
        _probe(
            "swap(uint256,uint256,address,bytes)",
            abi.encodeWithSignature("swap(uint256,uint256,address,bytes)", 0, 0, address(this), "")
        );
    }

    function test_61_Probe_Flash() public {
        _probe(
            "flash(address,uint256,bytes)",
            abi.encodeWithSignature("flash(address,uint256,bytes)", address(this), 0, "")
        );
    }

    function test_62_Probe_FlashLoan() public {
        _probe(
            "flashLoan(address,address,uint256,bytes)",
            abi.encodeWithSignature("flashLoan(address,address,uint256,bytes)", address(this), address(this), 0, "")
        );
    }

    function test_63_Probe_Execute() public {
        _probe("execute(bytes)", abi.encodeWithSignature("execute(bytes)", ""));
    }

    function test_64_Probe_Multicall() public {
        bytes[] memory data = new bytes[](0);
        _probe("multicall(bytes[])", abi.encodeWithSignature("multicall(bytes[])", data));
    }

    /* ------------- ORACLE / PRICE ------------- */

    function test_70_Probe_LatestAnswer() public {
        _probeView("latestAnswer()", abi.encodeWithSignature("latestAnswer()"));
    }

    function test_71_Probe_LatestRoundData() public {
        _probeView("latestRoundData()", abi.encodeWithSignature("latestRoundData()"));
    }

    function test_72_Probe_GetPrice() public {
        _probeView("getPrice()", abi.encodeWithSignature("getPrice()"));
    }

    function test_73_Probe_Peek() public {
        _probeView("peek()", abi.encodeWithSignature("peek()"));
    }

    function test_74_Probe_Consult() public {
        _probeView("consult(address,uint256)", abi.encodeWithSignature("consult(address,uint256)", address(this), 0));
    }

    /* ------------- GOVERNANCE / TIMELOCK ------------- */

    function test_80_Probe_Propose() public {
        address[] memory t;
        uint256[] memory v;
        bytes[] memory c;
        _probe(
            "propose(address[],uint256[],bytes[],string)",
            abi.encodeWithSignature("propose(address[],uint256[],bytes[],string)", t, v, c, "")
        );
    }

    function test_81_Probe_ExecuteProposal() public {
        _probe("execute(uint256)", abi.encodeWithSignature("execute(uint256)", 0));
    }

    function test_82_Probe_Queue() public {
        _probe("queue(uint256)", abi.encodeWithSignature("queue(uint256)", 0));
    }

    function test_83_Probe_Cancel() public {
        _probe("cancel(uint256)", abi.encodeWithSignature("cancel(uint256)", 0));
    }

    function test_84_Probe_Schedule() public {
        _probe(
            "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
            abi.encodeWithSignature(
                "schedule(address,uint256,bytes,bytes32,bytes32,uint256)",
                address(this),
                0,
                "",
                bytes32(0),
                bytes32(0),
                0
            )
        );
    }

    /* ------------- BRIDGE / MESSENGER ------------- */

    function test_90_Probe_Process() public {
        _probe("process(bytes)", abi.encodeWithSignature("process(bytes)", ""));
    }

    function test_91_Probe_ReceiveMessage() public {
        _probe("receiveMessage(bytes)", abi.encodeWithSignature("receiveMessage(bytes)", ""));
    }

    function test_92_Probe_Relay() public {
        _probe("relay(bytes)", abi.encodeWithSignature("relay(bytes)", ""));
    }

    function test_93_Probe_Claim() public {
        _probe("claim()", abi.encodeWithSignature("claim()"));
    }

    /* ------------- SELF-CALL / REENTRANCY SURFACE ------------- */

    function test_A0_EmptyCallDoesNotSelfDestruct() public {
        uint256 beforeLen = TARGET.code.length;
        (bool ok,) = TARGET.call{value: 0}("");
        uint256 afterLen = TARGET.code.length;
        emit log_named_uint("empty_call_ok", ok ? 1 : 0);
        assertEq(afterLen, beforeLen, "code size changed after empty call - investigate");
    }

    function test_A1_PrankAttacker_EmptyCall() public {
        address attacker = address(0xbad);
        vm.deal(attacker, 1 ether);
        vm.prank(attacker);
        (bool ok,) = TARGET.call{value: 0}("");
        emit log_named_uint("attacker_empty_call_ok", ok ? 1 : 0);
        assertTrue(TARGET.code.length > 0, "code wiped?");
    }

    function test_A2_DealAndCallDepositPath() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = TARGET.call{value: 0.01 ether}("");
        emit log_named_uint("value_call_ok", ok ? 1 : 0);
        // Do not assert ok - many contracts reject plain ETH; we only ensure no code wipe.
        assertGt(TARGET.code.length, 0, "code missing after value call");
    }

    /* ------------- helpers ------------- */

    function _probe(string memory name, bytes memory data) internal {
        (bool ok, bytes memory ret) = TARGET.call(data);
        emit Probe(name, ok, ret.length);
        emit log_named_string(name, ok ? "CALL_OK" : "REVERT_OR_NOSEL");
        assertTrue(true);
    }

    function _probeView(string memory name, bytes memory data) internal {
        (bool ok, bytes memory ret) = TARGET.staticcall(data);
        emit Probe(name, ok, ret.length);
        emit log_named_string(name, ok ? "VIEW_OK" : "REVERT_OR_NOSEL");
        if (ok && ret.length > 0) {
            emit log_named_bytes("ret", ret);
        }
        assertTrue(true);
    }
}
