import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("MarketplaceEscrowModule", (m) => {
  const productListingAddress = m.getParameter("_productListingAddress", "0x")
  const platformWallet = m.getParameter("_platformWallet", "0x2f4cA26741509c6ed0bF8F87aC8b0341386de9FC")

  const marketplaceEscrowContract = m.contract("MarketplaceEscrow", [productListingAddress, platformWallet]);

  return { marketplaceEscrowContract };
});