const ClientRaindrop = artifacts.require('./resolvers/ClientRaindrop/ClientRaindrop.sol')
const DateTime = artifacts.require('./components/DateTime.sol')
const HydroToken = artifacts.require('./_testing/HydroToken.sol')
const IdentityRegistry = artifacts.require('./_testing/IdentityRegistry.sol')
const KYCResolver = artifacts.require('./samples/KYCResolver.sol')
const OldClientRaindrop = artifacts.require('./_testing/OldClientRaindrop.sol')
const Snowflake = artifacts.require('./Snowflake.sol')


async function initialize (owner, users) {
  const instances = {}

  instances.DateTime = await DateTime.new( { from: owner })

  instances.HydroToken = await HydroToken.new({ from: owner })

  for (let i = 0; i < users.length; i++) {
    await instances.HydroToken.transfer(
      users[i].address,
      web3.utils.toBN(1000).mul(web3.utils.toBN(1e18)),
      { from: owner }
    )
  }


  instances.IdentityRegistry = await IdentityRegistry.new({ from: owner })

  instances.Snowflake = await Snowflake.new(
    instances.IdentityRegistry.address, instances.HydroToken.address, { from: owner }
  )

  instances.OldClientRaindrop = await OldClientRaindrop.new({ from: owner })

  instances.ClientRaindrop = await ClientRaindrop.new(
    instances.Snowflake.address, instances.OldClientRaindrop.address, 0, 0, { from: owner }
  )
  await instances.Snowflake.setClientRaindropAddress(instances.ClientRaindrop.address, { from: owner })

  instances.KYCResolver = await KYCResolver.new( {from: owner })
  
  console.log("KYC Resolver", instances.KYCResolver.address)
  console.log("Identity Registry", instances.IdentityRegistry.address)
  
  return instances
}

module.exports = {
  initialize: initialize
}
