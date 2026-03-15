import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// 定义并创建部署模块
const metaNFTModule = buildModule("MetaNFTModule", (m) => {
    // 声明要部署的 MetaNFT 合约
    const metaNFT = m.contract("MetaNFT");

    // 导出部署后的合约实例
    return {metaNFT};
});

// 导出整个部署模块,Hardhat ignition运行部署命令时，会识别这个导出的模块，并执行其中的合约部署逻辑
export default metaNFTModule;