// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "ds-test/test.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "../GoVest.sol";

contract FundingTest is DSTest {

    FundAdmin public fundAdmin;
    GoVest public vesting;

    Cheat cheat = Cheat(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    address fireTokenWhale = 0x5Ccb403182598e2bc3767eBc3987E7f4c511a5a8;
    IERC20 fireToken = IERC20(0x2033e559cdDFF6DD36ec204e3014FAA75a01052E);
    uint256 totalTime = 10000;
    uint256 offset = 1000;
    uint256 startTime = block.timestamp + offset;

    event Amount(uint256 amount);
    function setUp() public {
        fundAdmin = new FundAdmin();
        vesting = new GoVest(address(fireToken), startTime, totalTime, address(fundAdmin));

        cheat.label(address(fundAdmin), "fundAdmin");
        cheat.label(address(vesting), "vesting contract");
        cheat.label(address(fireToken), "FIRE token");
        cheat.label(address(fireTokenWhale), "FIRE Whale");
        cheat.label(address(cheat), "cheat");
    }

    function overflow(uint256 x, uint256 y) public pure returns (bool) {
        unchecked {
            return x + y < x;
        }
}

    function testFunding(uint256[] calldata seeds, bool choice) public {
        address[] memory recipients = new address[](seeds.length);
        uint256[] memory amounts    = new uint256[](seeds.length);
        uint256 totalAmount = 0;
        for (uint256 i; i < seeds.length; i++) {
            uint256 seed = seeds[i];
            // Using `i` guarantees no address collisions.
            recipients[i] = address(bytes20(keccak256(abi.encode(seed, i))));
            // Skip if the seed gives "bad" values, such as too big token amounts
            // or address collissions.
            if (overflow(totalAmount, seed) ||
                totalAmount + seed > fireToken.balanceOf(fireTokenWhale)) {
                continue;
            }
            amounts[i] = seed;
            totalAmount += amounts[i];
        }
        emit Amount(totalAmount);
        
        address funder;
        if (choice) {
            funder = address(this);
        } else {
            funder = address(fundAdmin);
        }

        cheat.prank(fireTokenWhale);
        fireToken.transfer(funder, totalAmount);

        emit Amount(fireToken.balanceOf(funder));

        cheat.startPrank(funder);
        fireToken.approve(address(vesting), totalAmount);

        vesting.addTokens(totalAmount);

        vesting.fund(recipients, amounts);
        cheat.stopPrank();

        require(vesting.initialLockedSupply() == totalAmount);
        for (uint i; i < seeds.length; i++) {
            uint256 stored = vesting.initialLocked(recipients[i]);

            emit Amount(stored);

            emit Amount(amounts[i]);

            require(stored == amounts[i]);
        }
        require(vesting.unallocatedSupply() == 0);
    }

    function testExample() public {
        assertTrue(true);
    }
}

contract FundAdmin {

}

interface Cheat {
    // Set block.timestamp
    function warp(uint256) external;
    // Set block.number
    function roll(uint256) external;
    // Set block.basefee
    function fee(uint256) external;
    // Loads a storage slot from an address
    function load(address account, bytes32 slot) external returns (bytes32);
    // Stores a value to an address' storage slot
    function store(address account, bytes32 slot, bytes32 value) external;
    // Signs data
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    // Computes address for a given private key
    function addr(uint256 privateKey) external returns (address);
    // Performs a foreign function call via terminal
    function ffi(string[] calldata) external returns (bytes memory);
    // Sets the *next* call's msg.sender to be the input address
    function prank(address) external;
    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called
    function startPrank(address) external;
    // Sets the *next* call's msg.sender to be the input address, and the tx.origin to be the second input
    function prank(address, address) external;
    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called, and the tx.origin to be the second input
    function startPrank(address, address) external;
    // Resets subsequent calls' msg.sender to be `address(this)`
    function stopPrank() external;
    // Sets an address' balance
    function deal(address who, uint256 newBalance) external;
    // Sets an address' code
    function etch(address who, bytes calldata code) external;
    // Expects an error on next call
    function expectRevert(bytes calldata) external;
    function expectRevert(bytes4) external;
    // Record all storage reads and writes
    function record() external;
    // Gets all accessed reads and write slot from a recording session, for a given address
    function accesses(address) external returns (bytes32[] memory reads, bytes32[] memory writes);
    // Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData).
    // Call this function, then emit an event, then call a function. Internally after the call, we check if
    // logs were emitted in the expected order with the expected topics and data (as specified by the booleans)
    function expectEmit(bool, bool, bool, bool) external;
    // Mocks a call to an address, returning specified data.
    // Calldata can either be strict or a partial match, e.g. if you only
    // pass a Solidity selector to the expected calldata, then the entire Solidity
    // function will be mocked.
    function mockCall(address, bytes calldata, bytes calldata) external;
    // Clears all mocked calls
    function clearMockedCalls() external;
    // Expect a call to an address with the specified calldata.
    // Calldata can either be strict or a partial match
    function expectCall(address, bytes calldata) external;
    function getCode(string calldata) external returns (bytes memory);
    // Label an address in test traces
    function label(address addr, string calldata label) external;
    // When fuzzing, generate new inputs if conditional not met
    function assume(bool) external;
}