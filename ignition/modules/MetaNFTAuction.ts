import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const metaNFTAuctionModule = buildModule("MetaNFTAuction", (m)=>{
    const metaNFTAuction = m.contract("MetaNFTAuction");
    return {metaNFTAuction};
})

export default metaNFTAuctionModule;
