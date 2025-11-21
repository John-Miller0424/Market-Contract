async function main() {
  const Market = await ethers.getContractFactory("Market");

  console.log("Deploying Market...");

  const owner = "0x1a503f080c8ba51cc517e610f9b9b622a1596917";
  const contract = await Market.deploy(owner);

  await contract.deployed();

  console.log("Contract deployed at:", contract.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
