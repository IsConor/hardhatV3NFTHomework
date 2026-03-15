import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
// 导入已部署的NFT拍卖合约基础模块（包含proxy、proxyAdmin等实例）
import metaNFTAuctionModule from "./MetaNFTAuctionProxyModule.js";

// 定义升级模块，命名为MetaNFTAuctionUpgradeModule
const metaNFTAuctionUpgradeModule = buildModule(
    "MetaNFTAuctionUpgradeModule",
    (m) => {
        // 获取部署账户（Hardhat配置中第0个账户，即代理管理员账户）
        const proxyAdminOwner = m.getAccount(0);

        // 复用基础模块中的proxyAdmin（管理员合约）和 proxy（代理合约）实例
        const {proxyAdmin, proxy} = m.useModule(metaNFTAuctionModule);

        // 部署V2版本的实现合约（MetaNFTAuctionV2）
        const auctionV2 = m.contract("MetaNFTAuctionV2");

        // 调用proxyAdmin的upgradeAndCall方法执行合约升级
        m.call(proxyAdmin, "upgradeAndCall", [proxy, auctionV2, "0x"], {
            from: proxyAdminOwner,
        });

        // 将代理合约地址绑定为MetaNFTAuctionV2类型，生成V2版交互实例
        const auction = m.contractAt("MetaNFTAuctionV2", proxy, {
            id: "MetaNFTAuctionV2AtProxy",
        });

        // 导出升级后的核心实例
        return {auction, proxyAdmin, proxy};
    }
);

export default metaNFTAuctionUpgradeModule;