pragma solidity ^0.8.0;

import { console2, Test } from "forge-std/Test.sol";

import "../../contracts/compound-v2-fork/WhitePaperInterestRateModel.sol";
import "../../contracts/compound-v2-fork/ComptrollerInterface.sol";
import "../../contracts/compound-v2-fork/CErc20Delegator.sol";
import "../../contracts/compound-v2-fork/CErc20Delegate.sol";
import "../../contracts/compound-v2-fork/Comptroller.sol";
import "../../contracts/utilities/MarketAidFactory.sol";
import "../../contracts/periphery/TokenWithFaucet.sol";
import "../../contracts/utilities/MarketAid.sol";
import "../../contracts/periphery/WETH9.sol";

import { RubiconMarket } from "contracts/RubiconMarket.sol";

import { ERC20FeeOnTransfer } from "test/contracts/mock/ERC20FeeOnTransfer.sol";

/// @notice proxy isn't used here
contract AuditTest is Test {
  //========================CONSTANTS========================
  address internal alice;
  uint256 internal alicePrivateKey;

  address internal bob;
  uint256 internal bobPrivateKey;

  address public owner;
  address FEE_TO = 0x0000000000000000000000000000000000000FEE;
  // core contracts
  RubiconMarket market;
  Comptroller comptroller;
  // test tokens
  TokenWithFaucet TEST;
  TokenWithFaucet TUSDC;
  TokenWithFaucet GUSD;
  WETH9 WETH;
  // Pools
  WhitePaperInterestRateModel irModel;
  CErc20Delegate bathTokenImplementation;
  CErc20Delegator bathTEST;
  CErc20Delegator bathTUSDC;
  // MarketAid
  MarketAidFactory marketAidFactory;

  ERC20FeeOnTransfer feeOnTransferToken;

  // deployRubiconProtocolFixture()
  function setUp() public {
    owner = msg.sender;
    // deploy Comptroller instance
    comptroller = new Comptroller();

    // deploy new Market instance and init
    market = new RubiconMarket();
    market.initialize(FEE_TO);
    market.setFeeBPS(0);

    // deploy test tokens
    TEST = new TokenWithFaucet(address(this), "Test", "TEST", 18);
    TUSDC = new TokenWithFaucet(address(this), "Test Stablecoin", "TUSDC", 6);
    GUSD = new TokenWithFaucet(address(this), "Gemini dollar", "GUSD", 2);
    WETH = new WETH9();

    // create InterestRateModel;
    // baseRate = 0.3, multiplierPerYear = 0.02
    irModel = new WhitePaperInterestRateModel(3e17, 2e16);
    bathTokenImplementation = new CErc20Delegate();
    bathTEST = new CErc20Delegator(
      address(TEST),
      ComptrollerInterface(address(comptroller)),
      irModel,
      2e26,
      "TestBathToken",
      "bathTEST",
      18,
      payable(owner),
      address(bathTokenImplementation),
      ""
    );
    bathTUSDC = new CErc20Delegator(
      address(TUSDC),
      ComptrollerInterface(address(comptroller)),
      irModel,
      2e15,
      "TestBathStablecoin",
      "bathTUSDC",
      6,
      payable(owner),
      address(bathTokenImplementation),
      ""
    );
    // support cToken market
    comptroller._supportMarket(CToken(address(bathTEST)));
    comptroller._supportMarket(CToken(address(bathTUSDC)));

    // add some $$$ to the Market
    TEST.faucet();
    TUSDC.faucet();
    // TEST.approve(address(market), type(uint256).max);
    // TUSDC.approve(address(market), type(uint256).max);
    // place ask and bid for TEST/TUSDC pair
    // market.offer(90e6, TUSDC, 100e18, TEST, address(this), owner); // offer with custom owner and recipient
    // market.offer(100e18, TEST, 110e6, TUSDC);

    // Aid for the Market
    marketAidFactory = new MarketAidFactory();
    marketAidFactory.initialize(address(market));

    (alice, alicePrivateKey) = makeAddrAndKey("Alice");
    (bob, bobPrivateKey) = makeAddrAndKey("Bob");

    feeOnTransferToken = new ERC20FeeOnTransfer();
  }

  //========================MARKET_TESTS========================
  // M01
  function testOfferFeeOnTransferToken () public {
    uint256 payAmount = 1000e18;
    uint256 buyAmount = 1000e6;

    feeOnTransferToken.mint(alice, payAmount * 2);

    vm.startPrank(alice);
    feeOnTransferToken.approve(address(market), type(uint256).max);

    uint256 offerOneId = market.offer(payAmount, ERC20(address(feeOnTransferToken)), buyAmount, TUSDC, alice, alice);
    (uint256 offerPayAmt,, uint256 offerBuyAmount,) = market.getOffer(offerOneId);

    /**
     * 900e18 feeOnTransferToken have been transferred to RubiconMarket,
     * so offerPayAmt should be 900e18 but is instead 1000e18
     * cause we don't check for the actual amount transferred before storing the value in `info`
     */
    assertEq(offerPayAmt, payAmount);

    uint256 offerTwoId = market.offer(payAmount, ERC20(address(feeOnTransferToken)), buyAmount, TUSDC, alice, alice);

    // RubiconMarket holds 1800e18 feeOnTransferToken instead of 2000e18
    assertEq(feeOnTransferToken.balanceOf(address(market)), 1800e18);

    vm.stopPrank();

    TUSDC.transfer(bob, buyAmount * 2);

    vm.startPrank(bob);

    TUSDC.approve(address(market), type(uint256).max);

    market.buy(offerOneId, payAmount);

    /**
     * When bob tries to buy 1000e18 feeOnTransferToken in exchange of 1000e6 TUSDC,
     * it fails cause only 800e18 feeOnTransferToken are left in the RubiconMarket.
     */
    vm.expectRevert();
    market.buy(offerTwoId, payAmount);

    assertEq(feeOnTransferToken.balanceOf(address(market)), 800e18);

    vm.stopPrank();
  }

  // M02
  function testBuyFeeLowDecimal() public {
    uint256 payAmount = 1000e18;
    uint256 buyAmount = 500e2;

    TEST.transfer(alice, payAmount);

    vm.startPrank(alice);
    TEST.approve(address(market), type(uint256).max);

    uint256 offerOneId = market.offer(payAmount, TEST, buyAmount, GUSD, alice, alice);
    (uint256 offerPayAmt,, uint256 offerBuyAmount,) = market.getOffer(offerOneId);

    vm.stopPrank();

    GUSD.transfer(bob, buyAmount * 2);

    vm.startPrank(bob);

    GUSD.approve(address(market), type(uint256).max);

    market.buy(offerOneId, payAmount);

    assertEq(GUSD.balanceOf(alice), buyAmount);

    /**
     * Mathematically, the fee should be: 500 * 0.0001 = 0.05
     * But in Solidity, the fee is calculated the following way:
     * amount * feeBPS / 100_000 = 50000 * 1 / 100_000 = 0
     * It returns 0 cause Solidity truncates down 0.5 to 0
     */
    assertEq(GUSD.balanceOf(FEE_TO), 0);

    vm.stopPrank();
  }
}
