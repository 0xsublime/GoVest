// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./Cheat.sol";
import "ds-test/test.sol";
import "../GoVest.sol";
import "solmate/tokens/ERC20.sol";

contract FundingTest is DSTest {

    // From GoVest contract
    event Claim(address indexed user, address claimer, uint256 amount);

    FundAdmin public fundAdmin;
    GoVest public vesting;

    Cheat cheat = (new Cheater()).getCheat();

    address fireTokenWhale = 0x5Ccb403182598e2bc3767eBc3987E7f4c511a5a8;
    FireToken fireToken = new FireToken("Ceramic Token", "FIRE", 18);
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

    function overflow(uint256 x, uint256 y) internal pure returns (bool) {
        unchecked {
            return x + y < x;
        }
    }

    function seed2Address(uint256 seed, uint256 salt) internal pure returns (address) {
        return address(bytes20(keccak256(abi.encode(seed, salt))));
    }

    function testFunding(uint256[] calldata seeds, bool choice) public {
        address[] memory recipients = new address[](seeds.length);
        uint256[] memory amounts    = new uint256[](seeds.length);
        uint256 totalAmount = 0;
        for (uint256 i; i < seeds.length; i++) {
            uint256 seed = seeds[i];
            recipients[i] = seed2Address(seed, i);
            // Skip if the seed gives "bad" values, such as too big token amounts
            // or address collissions.
            cheat.assume(!overflow(totalAmount, seed));
            amounts[i] = seed;
            totalAmount += amounts[i];
        }
        cheat.assume(totalAmount > 100_000);
        cheat.assume(type(uint256).max / totalTime >= totalAmount);
        
        address funder;
        if (choice) {
            funder = address(this);
        } else {
            funder = address(fundAdmin);
        }

        fireToken.mint(fireTokenWhale, totalAmount);

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

    function testClaim(uint256 _totalTime, uint256[] calldata seeds, bool choice) public {
        uint256 initialTimestamp = block.timestamp;
        testFunding(seeds, choice);
        for (uint256 i; i < seeds.length; i++) {
            address recipient = seed2Address(seeds[i], i);

            cheat.expectEmit(true, false, false, false);
            emit Claim(recipient, address(this), 0);
            vesting.claim(recipient);
        }
        cheat.warp(initialTimestamp + _totalTime / 2);
        cheat.warp(initialTimestamp + _totalTime);
    }

    function testExample() public {
        assertTrue(true);
    }
}

contract FireToken is ERC20 {

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}

    function mint(address recipient, uint256 amount) public {
        _mint(recipient, amount);
    }
}

contract FundAdmin {
}