// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol"; 
import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {HelperConfig, CodeConstants} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";


contract RaffleTest is Test, CodeConstants {
  Raffle public raffle;
  HelperConfig public helperConfig;

  uint256 entranceFee;
  uint256 interval;
  address vrfCoordinator;
  bytes32 gasLane;
  uint32 callbackGasLimit;
  uint256 subscriptionId;
  
  address public PLAYER = makeAddr("player");
  uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    /* Events */
  event RaffleEntered(address indexed player);
  event WinnerPicked(address indexed winner);

  function setUp() external {
    DeployRaffle deployer = new DeployRaffle();
    (raffle, helperConfig) = deployer.deployRaffle();
    HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
    entranceFee = config.entranceFee;
    interval = config.interval;
    vrfCoordinator = config.vrfCoordinator;
    gasLane = config.gasLane;
    callbackGasLimit = config.callbackGasLimit;
    subscriptionId = config.subscriptionId;

    vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
  }

  
  function testRaffleInitializesInOpenState() public view {
    assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
  }  
  
  function testRaffleRevertsWhenYouDontPayEnough() public {
    // Arrange
    vm.prank(PLAYER);
    // Act / ASSET 
    vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
    raffle.enterRaffle();
  }

  function testRaffleRecordsPlayersWhenTheyEnter() public {
    // Arrange 
    vm.prank(PLAYER);
    // Act 
    raffle.enterRaffle{value: entranceFee}();
    // Asset
    address playerRecorded = raffle.getPlayer(0);
    assert(playerRecorded == PLAYER);
  }
  
  function testEnteringRaffleEmitsEvent() public {
    // Arrange 
    vm.prank(PLAYER);
    // Act 
    vm.expectEmit(true, false, false, false, address(raffle));
    emit RaffleEntered(PLAYER);
    // Asset 
    raffle.enterRaffle{value: entranceFee}();
  }

  function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
    // Arrange
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1); // simulate the new block 
    raffle.performUpkeep("");
    // Act / Asset 
    vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    // Asset 
  }

  ///////////
  // upkeep
  ///////////
  function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
    // Arrange 
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1);

    // Act 
    (bool upkeepNeeded, ) = raffle.checkUpKeep("");

    // assert 
    assert(!upkeepNeeded);
  }

  function testCheckUpkeepReturnsFlaseIfRaffleIsntOpen() public {
    // Arrange 
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1); // simulate the new block 
    raffle.performUpkeep("");

    // Act 
    (bool upkeepNeeded, ) = raffle.checkUpKeep("");

    // Assert 
    assert(!upkeepNeeded);
  }

  // Challenge
  // testCheckUpkeepReturnsFalseIfEnoughtTimeHasPassed
  // testCheckUpkeepReturnsTrueWhenParametersAreGood

  ////////////////////
  // PERFORM UPKEEP 
  ///////////////////
  function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1); // simulate the new block 
    
    // Act / assert 
    raffle.performUpkeep("");
  }

  function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
    // Arrage 
    uint256 currentBalance = 0;
    uint256 numPlayers = 0;
    Raffle.RaffleState rState = raffle.getRaffleState();

    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    currentBalance = currentBalance + entranceFee;
    numPlayers = 1;

    // Act / Assert 
    vm.expectRevert(
      abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeeded.selector, currentBalance, numPlayers, rState)
    );
    raffle.performUpkeep("");
  }

  modifier raffleEntered() {
    vm.prank(PLAYER);
    raffle.enterRaffle{value: entranceFee}();
    vm.warp(block.timestamp + interval + 1);
    vm.roll(block.number + 1); 
    _;
  }

  function testPerformUpkeepUpdatesraffleStateAndEmitsRequestId() public raffleEntered {
    // arrange 

    // act 
    vm.recordLogs();
    raffle.performUpkeep("");
    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 requestId = entries[1].topics[1];

    // assert 
    Raffle.RaffleState raffleState = raffle.getRaffleState();
    assert(uint256(requestId) > 0);
    assert(uint256(raffleState) == 1);
  }

  //////////////////////////////////
  //// FULFILLRANDOMWORDS
  //////////////////////////////////
  modifier skipFork() {
    if(block.chainid != LOCAL_CHAIN_ID){
      return;
    }
    _;
  }

  function testFulFillrandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered skipFork{
    // Arrange 
    
    // Acc / assert 
    vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
    VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
  }

  function testFulfillrandomWordsPicksAWinnerResetsAndSensMoney() public raffleEntered skipFork {
    // Arrange 
    uint256 additionalEntrants = 3; // 4 people 
    uint256 startingIndex = 1;
    address expectedWinner = address(1);

    for(uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
      address newPlayer = address(uint160(i));
      hoax(newPlayer, 1 ether);
      raffle.enterRaffle{value: entranceFee}();
    }
    uint256 startingTimestamp = raffle.getLasTimeStamp();
    uint256 winnerStartingBalance = expectedWinner.balance;
    
    // Act 
    vm.recordLogs();
    raffle.performUpkeep("");
    Vm.Log[] memory entries = vm.getRecordedLogs();
    bytes32 requestId = entries[1].topics[1];
    VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

    // Assert -> be sure the winner is the selected
    address recentWinner = raffle.getRecentWinner();
    Raffle.RaffleState raffleState = raffle.getRaffleState();
    uint256 winnerBalance = recentWinner.balance;
    uint256 endingTimeStamp = raffle.getLasTimeStamp();
    uint256 prize = entranceFee * (additionalEntrants + 1);
    
    assert(recentWinner == expectedWinner);
    assert(uint256(raffleState) == 0);
    assert(winnerBalance == winnerStartingBalance + prize);
    assert(endingTimeStamp > startingTimestamp);
  }
}
