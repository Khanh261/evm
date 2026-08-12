import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MyDappModule = buildModule("MyDappModule", (m) => {
  const myDapp = m.contract("MyDapp");

  return { myDapp };
});

export default MyDappModule;
