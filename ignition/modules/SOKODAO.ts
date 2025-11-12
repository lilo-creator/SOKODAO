import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("SOKODAOModule", (m) => {
  const sokodaoContract = m.contract("SOKODAO", []);

  return { sokodaoContract };
});