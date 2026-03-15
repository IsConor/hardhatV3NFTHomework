// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MetaNFTAuction is Initializable {
    address admin;

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
        uint256 highestBidInDollar;
    }
    mapping(uint256 => mapping(address => uint256)) public bids;
    mapping(uint256 => mapping(address => uint256)) public bidMethods; // 0第一次报价 1eth 2token
    uint256 public auctionId;
    mapping(uint256 => Auction) public auctions;

    event StartBid(uint256 startingBid);
    event Bid(address indexed sender, uint256 amount, uint256 bidMethod);
    event Withdraw(address indexed bidder, uint256 amount);
    event EndBid(uint256 indexed auctionId);

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }
    modifier auctionNotEnd(uint256 auctionId_){
        require(!auctions[auctionId_].end, "ended");
        require(block.timestamp < auctions[auctionId_].startingTime + auctions[auctionId_].duration, "ended");
        _;
    }
    modifier auctionEnded(uint256 auctionId_){
        require(auctions[auctionId_].end, "not ended");
        require(block.timestamp > auctions[auctionId_].startingTime + auctions[auctionId_].duration, "not ended");
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
        require(duration >= 30, "invalid duration");
        require(paymentToken != address(0), "invalid payment token");
        auctions[auctionId] = Auction({
            end: false,
            nft: IERC721(nft),
            nftId: nftId,
            seller: payable(seller),
            startingTime: block.timestamp,
            startingPriceInDollar: startingPriceInDollar * 10**8,
            duration: duration,
            paymentToken: IERC20(paymentToken),
            highestBid: 0,
            highestBidder: address(0),
            highestBidInDollar: 0
        });
        auctionId++;



        // 检查当前合约是否有对应nft的授权？ 应该不用
        // 因为是卖家调用的此函数，所以直接授权即可
        // require(auctions[auctionId].nft.getApproved(nftId) == address(this),"no");

        // 授权给当前合约id为nftId的NFT
        auctions[auctionId].nft.approve(address(this), nftId);
        // 将id为nftId的NFT从卖家seller转入当前合约锁定
        auctions[auctionId].nft.safeTransferFrom(seller, address(this), nftId);
        // 触发开始拍卖事件
        emit StartBid(auctionId);
    }

    // 买家竞价
    function bid(uint256 auctionId_) external payable auctionNotEnd(auctionId_){
        Auction storage auction = auctions[auctionId_];
        uint256 allowance = auction.paymentToken.allowance(msg.sender, address(this));
        require(msg.value > 0 || allowance > 0, "invalid bid");
        require((msg.value > 0) != (allowance > 0), "only one of ETH or token");
        require(auction.startingTime > 0, "not started");

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
                require(bidMethod == 1, "invalid method");
            }
            uint256 price = getPriceInDollar(bidMethod);
            bidPrice = _toUsd(msg.value, 18, price);
            auction.highestBid = msg.value;
        } else {
            // 设置为token
            require(allowance > 0, "invalid payment");
            bidMethod = bidMethods[auctionId_][msg.sender];
            if (bidMethod == 0) {
                bidMethod = 2;
                bidMethods[auctionId_][msg.sender] = bidMethod;
            } else {
                require(bidMethod == 2, "invalid method");
            }
            uint256 price = getPriceInDollar(bidMethod);
            uint8 tokenDecimals = IERC20Metadata(address(auction.paymentToken)).decimals();
            bidPrice = _toUsd(allowance, tokenDecimals, price);
            auction.highestBid = allowance;
            IERC20(address(auction.paymentToken)).transferFrom(msg.sender, address(this), allowance);
        }
        require(auction.startingPriceInDollar < bidPrice, "invalid startingPrice");
        require(auction.highestBidInDollar < bidPrice, "invalid highestBid");
        auction.highestBidder = msg.sender;
        auction.highestBidInDollar = bidPrice;
        emit Bid(msg.sender, msg.value, bidMethod);
    }

    // 管理员在拍卖结束后调用bidSuccess方法分配资产
    function bidSuccess(uint256 auctionId_) external onlyAdmin auctionEnded(auctionId_){
        Auction storage auction = auctions[auctionId_];

        // 卖家获得竞拍所得ETH或者token
        uint256 bidMethod = bidMethods[auctionId_][auction.highestBidder];
        uint256 allowance = auction.paymentToken.allowance(address(this), auction.highestBidder);
        // 卖家获得相应的成交额 这里判断是ETH还是ERC20的token
        if(bidMethod == 1){
            // ETH
            (bool success,) = auction.seller.call{value: auction.highestBid}("");
            require(success, "not success");
        }else{
            // Token
            // 授权额度大于转账额度（疑问？这里直接给授权还是检查即可）
            require(allowance >= auction.highestBid, "invalid payment");
            auction.paymentToken.transferFrom(address(this), auction.seller, auction.highestBid);
        }
        
        // NFT应该转给最高出价者
        auction.nft.safeTransferFrom(address(this), auction.highestBidder, auction.nftId);
    }

    // 竞拍的人没有拍到，调用withdraw进行退款 结束才能提款
    function withdraw(uint256 auctionId_) external auctionEnded(auctionId_) returns (uint256) {
        Auction storage auction = auctions[auctionId_];
        // 出价最高的人不能退款
        require(auction.highestBidder!=msg.sender, "error");


        uint256 bidMethod = bidMethods[auctionId_][msg.sender];
        // 确认msg.sender应该退款的额度
        uint256 bal = bids[auctionId_][msg.sender];
        // 进行退款
        bids[auctionId_][msg.sender] = 0;
        if (bidMethod == 1) {
            // 退 ETH
            payable(msg.sender).transfer(bal);
        } else {
            // 退 ERC20 token
            IERC20(address(auction.paymentToken)).transferFrom(address(this), msg.sender, bal);
        }
        emit Withdraw(msg.sender, bal);
        return bal;
    }

    // 结束拍卖
    function endBidding(uint256 auctionId_) external onlyAdmin auctionNotEnd(auctionId_){
        
        Auction storage auction = auctions[auctionId_];

        // admin主动停止拍卖
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

    // 8位小数的usd
    function _toUsd(uint256 amount, uint256 amountDecimals, uint256 price)
        internal
        pure
        returns (uint256)
    {
        // amount is in smallest units; convert to USD using price decimals.
        uint256 scale = 10 ** amountDecimals;
        uint256 usd = (amount * price) / scale;
        return usd;
    }
    function getVersion() external pure returns (string memory) {
        return "MetaNFTAuctionV1";
    }
}