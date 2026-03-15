// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MetaNFTAuctionV2 is Initializable {
    address admin;
    uint8 private constant USD_DECIMALS = 8;

    struct Auction {
        // NFT 相关信息
        bool end;
        IERC721 nft;
        uint256 nftId;
        // 拍卖信息
        address payable seller;
        uint256 startingTime;
        address highestBidder;
        uint256 startingPriceInDollar;
        uint256 duration;
        IERC20 paymentToken;
        uint256 highestBid;
    }
    mapping(uint256 => mapping(address => uint256)) public bids;
    mapping(uint256 => mapping(address => uint256)) public bidMethods; // 0第一次报价 1eth 2token
    uint256 auctionId;
    mapping(uint256 => Auction) public auctions;

    event StartBid(uint256 startingBid);
    event Bid(address indexed sender, uint256 amount, uint256 bidMethod);
    event Withdraw(address indexed bidder, uint256 amount);
    event EndBid(uint256 indexed auctionId);

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }
    // 初始化
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin_) external initializer {
        require(admin_ != address(0), "invalid admin");
        admin = admin_;
    }

    // 卖家发起拍卖
    function start(
        address seller,
        uint256 nftId,
        address nft,
        uint256 startingPriceInDollar,
        uint256 duration,
        address paymentToken
    ) external onlyAdmin {
        require(nft != address(0), "invalid nft");
        require(duration > 60, "invalid duration");
        require(paymentToken != address(0), "invalid payment token");
        auctions[auctionId] = Auction({
            end: false,
            nft: IERC721(nft),
            nftId: nftId,
            seller: payable(seller),
            startingTime: block.timestamp,
            startingPriceInDollar: startingPriceInDollar,
            duration: duration,
            paymentToken: IERC20(paymentToken),
            highestBid: 0,
            highestBidder: address(0)
        });
        auctionId++;
        emit StartBid(auctionId);
    }

    // 买家竞价
    function bid(uint256 auctionId_) external payable {
        Auction memory auction = auctions[auctionId_];
        uint256 allowance = auction.paymentToken.allowance(msg.sender, address(this));
        require(msg.value > 0 || allowance > 0, "invalid bid");
        require(msg.value > 0 && allowance > 0, "only one of ETH or token");
        require(auction.startingTime > 0, "not started");
        require(!auction.end, "ended");
        require(block.timestamp < auction.startingTime + auction.duration, "ended");
        if (auction.highestBidder != address(0)) {
            bids[auctionId_][auction.highestBidder] += auction.highestBid;
        }
        uint256 bidMethod;
        uint256 bidPrice;
        //  判断支付方式
        if (msg.value > 0) {
            bidMethod = bidMethods[auctionId_][msg.sender];
            if (bidMethod == 0) {
                // 第一次报价 设置为eth
                bidMethod = 1;
                bidMethods[auctionId_][msg.sender] = bidMethod;
            } else {
                require(bidMethod == 1, "invalid bid");
            }
            uint256 price = getPriceInDollar(bidMethod);
            uint8 priceDecimals = getPriceDecimals(bidMethod);
            bidPrice = _toUsd(msg.value, 18, price, priceDecimals);
            auction.highestBid = msg.value;
        } else {
            // 设置为token
            require(allowance > 0, "invalid payment");
            bidMethod = bidMethods[auctionId_][msg.sender];
            if (bidMethod == 0) {
                bidMethod = 2;
                bidMethods[auctionId_][msg.sender] = bidMethod;
            } else {
                require(bidMethod == 2, "invalid bid");
            }
            uint256 price = getPriceInDollar(bidMethod);
            uint8 priceDecimals = getPriceDecimals(bidMethod);
            uint8 tokenDecimals = IERC20Metadata(address(auction.paymentToken)).decimals();
            bidPrice = _toUsd(allowance, tokenDecimals, price, priceDecimals);
            auction.highestBid = allowance;
            IERC20(address(auction.paymentToken)).transferFrom(msg.sender, address(this), allowance);
        }
        require(auction.startingPriceInDollar < bidPrice, "invalid startingPrice");
        auction.highestBidder = msg.sender;
        emit Bid(msg.sender, msg.value, bidMethod);
    }

    function withdraw(uint256 auctionId_) external {
        Auction memory auction = auctions[auctionId_];
        // 结束才能提款
        require(block.timestamp >= auction.startingTime + auction.duration, "ended");
        uint256 bidMethod = bidMethods[auctionId_][msg.sender];
        uint256 bal = bids[auctionId_][msg.sender];
         bids[auctionId_][msg.sender] = 0;
        if (bidMethod == 1) {
            payable(msg.sender).transfer(bal);
        } else {
            IERC20(address(auction.paymentToken)).transferFrom(address(this), msg.sender, bal);
        }
        emit Withdraw(msg.sender, bal);
    }

    // 结束拍卖
    function endBidding(uint256 auctionId_) external {
        Auction memory auction = auctions[auctionId_];
        auction.end = true;
        emit EndBid(auctionId_);
    }

    function getPriceInDollar(uint256 bidMethod) public view returns (uint256) {
        AggregatorV3Interface dataFeed;
        //eth
        if (bidMethod == 1) {
            dataFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        } else {
            // usdc
            dataFeed = AggregatorV3Interface(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E);
        }
        (
            /* uint80 roundId */
            ,
            int256 answer,
            /*uint256 startedAt*/
            ,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = dataFeed.latestRoundData();
        return uint256(answer);
    }

    function getPriceDecimals(uint256 bidMethod) public view returns (uint8) {
        AggregatorV3Interface dataFeed;
        if (bidMethod == 1) {
            dataFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        } else {
            dataFeed = AggregatorV3Interface(0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E);
        }
        return dataFeed.decimals();
    }

    function _toUsd(uint256 amount, uint8 amountDecimals, uint256 price, uint8 priceDecimals)
        internal
        pure
        returns (uint256)
    {
        uint256 scale = 10 ** uint256(amountDecimals);
        uint256 usd = (amount * price) / scale;
        if (priceDecimals > USD_DECIMALS) {
            usd /= 10 ** uint256(priceDecimals - USD_DECIMALS);
        } else if (priceDecimals < USD_DECIMALS) {
            usd *= 10 ** uint256(USD_DECIMALS - priceDecimals);
        }
        return usd;
    }
    function getVersion() external pure returns (string memory) {
        return "MetaNFTAuctionV2";
    }
}