import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// 定义代理部署模块，负责部署实现合约、代理合约、配置管理员
const metaNFTAuctionProxyModule = buildModule(
    "MetaNFTAuctionProxyModule",
    (m) => {
        // 1.获取部署账户（第0个账户，对应hardhat配置的私钥/账户列表）
        const proxyAdminOwner = m.getAccount(0);

        // 2.部署 MetaNFTAuction 实现合约（仅部署，不初始化）
        const auctionImpl = m.contract("MetaNFTAuction");

        // 3.编码初始化函数调用（给代理合约部署时执行）
        const encodeFunctionCall = m.encodeFunctionCall(
            auctionImpl,    // 要调用的合约（实现合约）
            "initialize",   // 要调用的初始化函数名（非构造函数）
            [proxyAdminOwner], // 初始化函数的参数（管理员地址）
        );

        // 4.部署透明可升级代理合约
        const proxy = m.contract("TransparentUpgradeableProxy", [
            auctionImpl,        // 参数1:实现合约的地址
            proxyAdminOwner,    // 参数2:代理的初始管理员地址
            encodeFunctionCall, // 参数3:代理部署后要执行的初始化调用数据
        ]);

        // 5.从代理合约的 AdminChanged 事件中读取新管理员地址
        const proxyAdminAddress = m.readEventArgument(
            proxy,              // 监听的合约实例
            "AdminChanged",     // 要读取的事件名
            "newAdmin",         // 要读取的事件参数名
        );

        // 6.根据事件获取的地址，绑定 ProxyAdmin 合约实例
        const proxyAdmin = m.contractAt("ProxyAdmin", proxyAdminAddress);

        // 7.导出管理员合约和代理合约的实例（供其他模块使用）
        return {proxyAdmin, proxy};
    }
);

// 定义业务模块，复用代理模块的部署结果，封装成业务可用的合约实例
const metaNFTAuctionModule = buildModule("MetaNFTAuctionModule", (m)=>{
    // 1. 复用上面的代理部署模块，获取已部署的 proxy 和 proxyAdmin 实例
    const {proxy, proxyAdmin} = m.useModule(metaNFTAuctionProxyModule);
    
    // 2. 将代理合约地址绑定为 MetaNFAuction 类型（用户实际交互入口）
    const auction = m.contractAt("MetaNFTAuction", proxy);

    // 3. 导出最终可用的实例（auction 是业务交互入口）
    return {auction, proxy, proxyAdmin};
});

// 导出主模块
export default metaNFTAuctionModule;