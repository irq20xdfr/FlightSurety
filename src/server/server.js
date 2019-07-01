import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import FlightSuretyData from '../../build/contracts/FlightSuretyData.json'
import Config from './config.json';
import Web3 from 'web3';
import express from 'express';
require('babel-polyfill')
const bodyParser = require('body-parser')

let config = Config['localhost'];
let web3 = new Web3(new Web3.providers.WebsocketProvider(config.url.replace('http', 'ws')));
web3.eth.defaultAccount = web3.eth.accounts[0];

const flightSuretyApp = new web3.eth.Contract(FlightSuretyApp.abi, config.appAddress)
const flightSuretyData = new web3.eth.Contract(FlightSuretyData.abi, config.dataAddress)
const NUMBER_OF_ACCOUNTS = 50
const NUMBER_OF_ORACLES = 30

const Server = {
  oracles: [],
  flights: [],
  states: {
    0: 'unknown',
    10: 'on time',
    20: 'late due to airline',
    30: 'late due to weather',
    40: 'late due to technical reason',
    50: 'late due to other reason'
  },

  init: async function (numberOracles) {
    // EVENTS LISTENERS
    flightSuretyApp.events.OracleRegistered()
      .on('data', log => {
        const { event, returnValues: { indexes } } = log
        console.log(`${event}: indexes ${indexes[0]} ${indexes[1]} ${indexes[2]}`)
      })
      .on('error', error => { console.log(error) })

    flightSuretyData.events.AirlineRegistered()
      .on('data', log => {
        const { returnValues: { origin, newAirline } } = log
        console.log(`${origin} registered ${newAirline}`)
      })
      .on('error', error => { console.log(error) })

    flightSuretyApp.events.FlightRegistered()
      .on('data', async log => {
        const {
          event,
          returnValues: { flight, to, landing }
        } = log
        console.log(`${event}: ${flight} to ${to} landing ${landing}`)

        // store new flight
        const indexFlightKeys = await flightSuretyData.methods.indexFlightKeys().call()
        const key = await flightSuretyData.methods.flightKeys(indexFlightKeys).call()
        const flightObj = await flightSuretyData.methods.flights(key).call()
        for (let j = 0; j < 9; j++) {
          delete flightObj[j]
        }
        this.flights.push({
          index: indexFlightKeys,
          key: key,
          flight: flightObj
        })
      })
      .on('error', error => { console.log(error) })

    let self = this;
    flightSuretyApp.events.OracleRequest()
      .on('error', error => { console.log(error) })
      .on('data', async log => {
        const {
          event,
          returnValues: { index, flight, destination, timestamp }
        } = log

        console.log(`${event}: index ${index}, flight ${flight}, to ${destination}, landing ${timestamp}`)
        await self.submitResponses(flight, destination, timestamp)
      })

    flightSuretyApp.events.OracleReport()
      .on('data', log => {
        const {
          event,
          returnValues: { flight, destination, timestamp, status }
        } = log
        console.log(`${event}: flight ${flight}, to ${destination}, landing ${timestamp}, status ${this.states[status]}`)
      })
    
    flightSuretyApp.events.FlightStatusInfo()
      .on('data', log => {
        const {
          event,
          returnValues: { flight, destination, timestamp, status }
        } = log
        console.log(`${event}: flight ${flight}, to ${destination}, landing ${timestamp}, status ${this.states[status]}`)
        self.updateFlights();
      })
      .on('error', error => { console.log(error) })

    flightSuretyApp.events.FlightProcessed()
      .on('data', log => {
        const { event, returnValues: { flight, destination, timestamp, statusCode } } = log
        console.log(`${event}: flight ${flight}, to ${destination}, landing ${timestamp}, status ${this.states[statusCode]}`)
      })

    flightSuretyData.events.Funded()
      .on('data', log => {
        const { returnValues: { airline } } = log
        console.log(`${airline} provided funding`)
      })
      .on('error', error => console.log(error))

    flightSuretyApp.events.WithdrawRequest()
      .on('data', log => {
        const { event, returnValues: { recipient } } = log
        console.log(`${event} from ${recipient}`)
      })

    flightSuretyData.events.Paid()
      .on('data', log => {
        const { event, returnValues: { recipient, amount } } = log
        console.log(`${event} ${amount} to ${recipient}`)
      })


    flightSuretyData.events.Credited()
      .on('data', log => {
        const { event, returnValues: { passenger, amount } } = log
        console.log(`${event} ${amount} to ${passenger}`)
      })

    flightSuretyData.events.FlightBought()
    .on('data', log => {
      const { event, returnValues: { passenger, flightNo } } = log
      console.log(`${event} ${passenger} for flight ${flightNo}`)
    })

    flightSuretyData.events.CreditingInsurees()
    .on('data', log => {
      const { event } = log
      console.log(`${event}`)
    })


    flightSuretyApp.events.Prueba()
    .on('data', log => {
      const { event } = log
      console.log(`${event}`)
    })


    
    
    await flightSuretyData.methods.authorizeCaller(flightSuretyApp._address)

    
    this.oracles = (await web3.eth.getAccounts()).slice(NUMBER_OF_ACCOUNTS - numberOracles)
    
    const REGISTRATION_FEE = await flightSuretyApp.methods.REGISTRATION_FEE().call()
    this.oracles.forEach(async account => {
      try {
        await flightSuretyApp.methods.registerOracle().send({
          from: account,
          value: REGISTRATION_FEE,
          gas: 4712388,
          gasPrice: 100000000000
        })
      } catch (error) {
         console.log("error registering oracle "+error.message)
      }
    });

   
    this.updateFlights()
  },

  submitResponses: async function (flight, destination, timestamp) {
    this.oracles.forEach(async oracle => {
      
      const statusCode = 20;//(Math.floor(Math.random() * 5) + 1) * 10
      
      const oracleIndexes = await flightSuretyApp.methods.getMyIndexes().call({ from: oracle })
      oracleIndexes.forEach(async index => {
        try {
          await flightSuretyApp.methods.submitOracleResponse(
            index,
            flight,
            destination,
            +timestamp,
            statusCode
          ).send({ from: oracle, gas: 4712388,
            gasPrice: 100000000000 })
        } catch (error) {
          console.log("Error oracle" + error.message+" "+flight+"-"+destination+"-"+timestamp)
          //console.log(error);
        }
      })
    })
  },

  updateFlights: async function () {
    
    this.flights = []
    try {
      const indexFlightKeys = await flightSuretyData.methods.indexFlightKeys().call()
      for (let i = 0; i < indexFlightKeys + 1; i++) {
        const key = await flightSuretyData.methods.flightKeys(i).call()
        const flight = await flightSuretyData.methods.flights(key).call()
        for (let j = 0; j < 9; j++) {
          delete flight[j]
        }
        
        this.flights.push({
          index: i,
          key: key,
          flight: flight
        })
      }
    } catch (error) {
       console.log('zero flights')
    }
  }
}

Server.init(NUMBER_OF_ORACLES)





flightSuretyApp.events.OracleRequest({
    fromBlock: 0
  }, function (error, event) {
    if (error) console.log(error)
    console.log(event)
});

const app = express();
app.use(bodyParser.json())
app.use(function (req, res, next) {
  res.header('Access-Control-Allow-Origin', '*')
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept')
  next()
})
app.use(express.json())


app.get('/api', (req, res) => {
    res.send({
      message: 'An API for use with your Dapp!'
    })
})
app.get('/flights', (req, res) => {
  res.json(Server.flights)
})

export default app;


