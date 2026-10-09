// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PrismRiot} from "../src/PrismRiot.sol";

/// @dev Test-only factory: demonstrates receipt and forwarding of constructor supply.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (PrismRiot) {
        return new PrismRiot{salt: salt}();
    }

    function move(PrismRiot token, address recipient, uint256 amount) external returns (bool) {
        return token.transfer(recipient, amount);
    }
}

contract PrismRiotTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    PrismRiot private token;
    address private deployer;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        vm.prank(deployer);
        token = new PrismRiot();
    }

    function test_metadataAndEntireSupplyBelongToDeployer() public view {
        assertEq(token.name(), "PrismRiot");
        assertEq(token.symbol(), "PRIO");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(deployer, spender), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit IERC20.Transfer(address(0), alice, SUPPLY);
        vm.prank(alice);
        PrismRiot another = new PrismRiot();
        assertEq(another.balanceOf(alice), SUPPLY);
    }

    function test_factoryGetsSupplyAndForwardsExactLaunchAmounts() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        bytes32 salt = keccak256("local deployment");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(PrismRiot).creationCode))
                    )
                )
            )
        );
        PrismRiot launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        uint256 swarm = SUPPLY / 10;
        // The pool amount is a test fixture, not a launch economics decision.
        uint256 seed = SUPPLY / 5;
        assertTrue(factory.move(launched, distributor, swarm));
        assertTrue(factory.move(launched, poolManager, seed));
        assertTrue(factory.move(launched, alice, SUPPLY - swarm - seed));
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), seed);
        assertEq(launched.balanceOf(alice), SUPPLY - swarm - seed);

        vm.prank(distributor);
        assertTrue(launched.transfer(bob, swarm));
        assertEq(launched.balanceOf(bob), swarm);
        assertEq(launched.balanceOf(distributor), 0);

        vm.prank(poolManager);
        assertTrue(launched.transfer(spender, 100 ether));
        assertEq(launched.balanceOf(spender), 100 ether);
        vm.prank(spender);
        assertTrue(launched.transfer(poolManager, 100 ether));
        assertEq(launched.balanceOf(spender), 0);
        assertEq(launched.balanceOf(poolManager), seed);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_transferDeliversExactAmountAndEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 123 ether);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 123 ether));
        assertEq(token.balanceOf(deployer), SUPPLY - 123 ether);
        assertEq(token.balanceOf(alice), 123 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_canTransferEntireSupply() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_selfTransferDoesNotChangeBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_zeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_approveEmitsEventAndCanBeReplacedAndRevoked() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(deployer, spender, 100 ether);
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, 100 ether));
        assertEq(token.allowance(deployer, spender), 100 ether);
        assertTrue(token.approve(spender, 40 ether));
        assertEq(token.allowance(deployer, spender), 40 ether);
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 1);
    }

    function test_transferFromConsumesAllowanceAndEmitsTransfer() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(deployer, alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 40 ether));
        assertEq(token.allowance(deployer, spender), 60 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 40 ether);
        assertEq(token.balanceOf(alice), 40 ether);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, 60 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(bob), 60 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToSelfConsumesAllowanceWithoutChangingBalance() public {
        vm.prank(deployer);
        token.approve(spender, 10 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, 10 ether));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_maxAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_transferAboveBalanceRevertsWithoutChanges() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_emptyAccountCannotTransfer() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferFromAboveAllowanceRevertsWithoutChanges() public {
        vm.prank(deployer);
        token.approve(spender, 7);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 7, 8));
        vm.prank(spender);
        token.transferFrom(deployer, alice, 8);
        assertEq(token.allowance(deployer, spender), 7);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_transferFromAboveBalanceRollsBackAllowance() public {
        vm.prank(deployer);
        token.approve(spender, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, alice, SUPPLY + 1);
        assertEq(token.allowance(deployer, spender), SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approvalDoesNotAuthorizeAnotherSpender() public {
        vm.prank(deployer);
        token.approve(spender, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, alice, 1);
        assertEq(token.allowance(deployer, spender), 100 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 100 ether);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 1);
        assertEq(token.allowance(deployer, address(0)), 0);
    }

    function test_transferFromZeroRecipientRollsBackAllowance() public {
        vm.prank(deployer);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 100);
        assertEq(token.allowance(deployer, spender), 100);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_nativeCurrencyIsRejected() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
        assertEq(alice.balance, 1 ether);
    }

    function test_noMintBurnAdminOrUpgradeEntrypoints() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        bytes[] memory calls = new bytes[](12);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("freeze(address)", alice);
        calls[7] = abi.encodeWithSignature("seize(address)", alice);
        calls[8] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[9] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[10] = abi.encodeWithSignature("initialize(address)", bob);
        calls[11] = abi.encodeWithSignature("setMinter(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            vm.prank(deployer);
            (bool privileged,) = address(token).call(calls[i]);
            assertFalse(privileged, "deployer reached an unwanted entrypoint");
            vm.prank(bob);
            (bool publicCall,) = address(token).call(calls[i]);
            assertFalse(publicCall, "stranger reached an unwanted entrypoint");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100 ether);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_runtimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf4 && opcode != 0xf2 && opcode != 0xff, "forbidden opcode");
            }
        }
    }

    function testFuzz_transfersConserveSupply(uint256 rawAmount, uint256 rawReturnAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        uint256 returnAmount = bound(rawReturnAmount, 0, amount);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        vm.prank(alice);
        assertTrue(token.transfer(deployer, returnAmount));
        assertEq(token.balanceOf(alice), amount - returnAmount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount + returnAmount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndAllowance(uint256 rawApproval, uint256 rawAmount) public {
        uint256 approval = bound(rawApproval, 0, SUPPLY);
        uint256 amount = bound(rawAmount, 0, approval);
        vm.prank(deployer);
        assertTrue(token.approve(spender, approval));
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, amount));
        assertEq(token.allowance(deployer, spender), approval - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferToZeroAlwaysReverts(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, 0, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_cannotTransferAboveSupply(uint256 rawAmount) public {
        uint256 amount = bound(rawAmount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, amount)
        );
        vm.prank(deployer);
        token.transfer(alice, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
