import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
const metaNFTAuctionModule = buildModule("MetaNFTAuctionV2", (m) => {
  const metaNFTAuction = m.contract("MetaNFTAuctionV2")
  return { metaNFTAuction };
});
export default metaNFTAuctionModule;