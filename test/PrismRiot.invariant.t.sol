// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PrismRiot} from "../src/PrismRiot.sol";

/// @dev All token movement stays within these actors, making conservation observable.
contract TokenHandler is Test {
    PrismRiot public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PrismRiot token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        uint256 amount = bound(rawAmount, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    // Expected failures leave the ghost ledger unchanged. The invariants therefore check
    // rollback of every tracked balance and allowance, including unrelated actor pairs.
    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(to, amount);
    }

    function transferFromAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 rawAmount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, to, amount);
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, to, 1);
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        uint256 amount = bound(rawAmount, 0, maximum);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract PrismRiotInvariantTest is StdInvariant, Test {
    PrismRiot private token;
    TokenHandler private handler;
    address[4] private actors;

    function setUp() public {
        actors = [makeAddr("holder one"), makeAddr("holder two"), makeAddr("holder three"), makeAddr("holder four")];
        vm.prank(actors[0]);
        token = new PrismRiot();
        handler = new TokenHandler(token, actors);

        // Reach funded holders and both finite/infinite approvals before the random sequence.
        // All setup movements go through the token and update the independent ledger.
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(0, i, 250_000_000 * 10 ** 18);
        }
        for (uint256 i; i < actors.length; ++i) {
            handler.approve(i, (i + 1) % actors.length, 125_000_000 * 10 ** 18);
            handler.approve(i, i, type(uint256).max);
        }

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = TokenHandler.transfer.selector;
        selectors[1] = TokenHandler.approve.selector;
        selectors[2] = TokenHandler.transferFrom.selector;
        selectors[3] = TokenHandler.transferAboveBalance.selector;
        selectors[4] = TokenHandler.transferFromAboveBalance.selector;
        selectors[5] = TokenHandler.revokeAndReject.selector;
        selectors[6] = TokenHandler.transferToZero.selector;
        selectors[7] = TokenHandler.transferFromToZero.selector;
        selectors[8] = TokenHandler.approveZeroSpender.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_supplyAndBalancesMatchIndependentModel() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_allowancesMatchIndependentModel() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
