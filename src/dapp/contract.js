import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import FlightSuretyData from '../../build/contracts/FlightSuretyData.json';
import Config from './config.json';
import Web3 from 'web3';

export default class Contract {
    
    constructor(network, callback) {

        let config = Config[network];
        if (window.ethereum) {
            // use metamask's providers
            // modern browsers
            this.web3 = new Web3(window.ethereum)
            // Request accounts access
            try {
              window.ethereum.enable()
            } catch (error) {
              console.error('User denied access to accounts')
            }
          } else if (window.web3) {
            // legacy browsers
            this.web3 = new Web3(web3.currentProvider)
          } else {
            // fallback for non dapp browsers
            this.web3 = new Web3(new Web3.providers.HttpProvider(config.url))
          }

          let self = this;
          window.ethereum.on('accountsChanged', function (accounts) {
            //self.owner = accounts[0];
          })
      
          // Load contract
          this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress)
          this.flightSuretyData = new this.web3.eth.Contract(FlightSuretyData.abi, config.appAddress)

          console.log(this.flightSuretyData.events);



          

        this.initialize(callback);
        this.owner = null;

    }

    async withdraw () {
      let self = this;
      await this.flightSuretyApp.methods
        .withdraw()
        .send({ from: self.owner })
    }
    registerAirlineRegisteredEvent(callback){
      this.flightSuretyApp.events.AirlineRegistered({
        fromBlock: 0
    }, (error, event) => { console.log(event);
      callback(event);  
    });
    }

    initialize(callback) {
        this.web3.eth.getAccounts((error, accts) => {
           
            this.owner = accts[0];

            let counter = 1;
            callback();
        });
    }

    isOperational(callback) {
       let self = this;
       self.flightSuretyApp.methods
            .operational()
            .call({ from: self.owner}, callback);
    }

    async registerFlight (takeOff, landing, flight, price, from, to) {
        try {
          const priceInWei = this.web3.utils.toWei(price.toString(), 'ether')
          await this.flightSuretyApp.methods
            .registerFlight(takeOff, landing, flight, priceInWei, from, to)
            .send({ from: this.owner })
          return {
            address: this.owner,
            error: ''
          }
        } catch (error) {
          return {
            address: this.owner,
            error: error
          }
        }
    }

    fund (amount, callback) {
        let self = this
        self.flightSuretyApp.methods
          .fund()
          .send({
            from: self.owner,
            value: self.web3.utils.toWei(amount, 'ether')
          }, (error, result) => {
            callback(error, { address: self.owner, amount: amount })
          })
      }

      async countAirlines(callback) {
        let self = this;
        await self.flightSuretyApp.methods
          .airlinesCount()
          .call({
            from: self.owner,
          }, (error, result) => {
            this.totalAirlines = result;
            callback(result, self.owner);
          })
      }

    async llama () {
        let self = this;
        await self.flightSuretyApp.methods
          .airlinesCount()
          .call({
            from: self.owner,
          }, (error, result) => {
            console.log("regreso "+result);
          })
      }

    async registerAirline (airline) {
        let self = this;
        try {
          await this.flightSuretyApp.methods
            .registerAirline(airline)
            .send({ from: this.owner })
          const votes = await this.flightSuretyApp.methods.votesLeft(airline).call()
          return {
            address: self.owner,
            votes: votes
          }
        } catch (error) {
          return {
            error: error
          }
        }
      }

      async buy (flight, to, landing, price, insurance) {
        let self = this;
        let total = +price + +insurance
        total = total.toString()
        const amount = this.web3.utils.toWei(insurance.toString(), 'ether')
        try {
          console.log(flight);
          console.log(to);
          console.log(+landing);
          console.log(amount);
          
          await self.flightSuretyApp.methods
            .buy(flight, to, +landing, amount)
            .send({
              from: self.owner,
              value: self.web3.utils.toWei(total.toString(), 'ether')
            })
          return { passenger: self.owner }
        } catch (error) {
          console.log(error)
          return {
            error: error
          }
        }
      }


      async fetchFlightStatus (flight, destination, landing) {
        let self = this;
        try {
          console.log(flight);
          console.log(destination);
          console.log(landing);
          
          await this.flightSuretyApp.methods
            .fetchFlightStatus(flight, destination, landing)
            .send({ from: self.owner })
        } catch (error) {
          return {
            error: error
          }
        }
      }
}