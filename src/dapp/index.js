
import DOM from './dom';
import Contract from './contract';
import './bootstrap.css'
import './flightsurety.css';


(async() => {

    let result = null;

    let contract = new Contract('localhost', () => {

        // Read transaction
        contract.isOperational((error, result) => {
            console.log(error,result);
            display('Operational Status', 'Check if contract is operational', [ { label: 'Operational Status', error: error, value: result} ]);
        });


        function fetchAndAppendFlights () {
          fetch('http://localhost:3000/flights')
            .then(res => {
              return res.json()
            })
            .then(flights => {
              flights.forEach(flight => {
                
                if (flight.flight.statusCode == 0) {
                  let {
                    index,
                    flight: { price, flightNo, from, to, takeOff, landing }
                  } = flight
                  price = price / 1000000000000000000
                  
                  let datalist = DOM.elid('flights')
                  let option = DOM.option({ value: `${index} - ${price} ETH - ${flightNo} - ${from} - ${parseDate(+takeOff)} - ${to} - ${parseDate(+landing)}` })
                  datalist.appendChild(option)
                  
                  datalist = DOM.elid('oracle-requests')
                  option = DOM.option({ value: `${flightNo} - ${to} - ${parseDate(+landing)}` })
                  datalist.appendChild(option)
                }
              })
            })
        }
        fetchAndAppendFlights()
    

        // User-submitted transaction
        DOM.elid('submit-oracle').addEventListener('click', () => {
            let input = DOM.elid('oracle-request').value;
            input = input.split('-');
            input = input.map(el => { return el.trim() });
           
            let [flightNum, destination, landing] = input;
            
         
            // Fetch args from server
            fetch('http://localhost:3000/flights')
              .then(res => { return res.json() })
              .then(flights => {
                return flights.filter(ele => { return ele.flight.flightNo == flightNum })
              })
              .then(async flightObj => {
                console.log(flightObj);
                const { flight: { landing } } = flightObj[0]
                contract.fetchFlightStatus(flightNum, destination, landing);
                display('Oracles', 'Trigger oracles', [ { label: 'Fetch Flight Status', error: '', value: flightNum + ' ' + destination } ]);
              })

        });

        DOM.elid('register-flight').addEventListener('click', async () => {
            const takeOff = new Date(DOM.elid('rf-takeoff').value).getTime();
            const landing = new Date(DOM.elid('rf-landing').value).getTime();
            const flight = DOM.elid('rf-flight').value;
            const from = DOM.elid('rf-from').value;
            const to = DOM.elid('rf-to').value;
            const price = DOM.elid('rf-price').value;
            await contract.registerFlight(
              takeOff,
              landing,
              flight,
              price,
              from,
              to)
          });


          DOM.elid('fund').addEventListener('click', () => {
            let amount = DOM.elid('f-amount').value
            contract.fund(amount, (error, result) => {
              display(`Airline ${cutAddress(result.address)}`, 'Airline Funding', [{
                label: 'Funding',
                error: error,
                value: `${result.amount} ETH` }])
            })
          })


          DOM.elid('register-airline').addEventListener('click', async () => {
            const airlineToBeAdded = DOM.elid('ra-address').value;
            
            let lastAirlineCount = contract.totalAirlines;
            const { address, votes, error } = await contract.registerAirline(airlineToBeAdded)
            contract.countAirlines((result, ownerAdd) => {
              display('Current Airlines', 'Current Airline Count', [ { label: 'Total', error: error, value:  result+" counting owner address that is registered at constructor: "+cutAddress(ownerAdd)} ]);
              console.log("last "+lastAirlineCount);
              console.log("last "+result);
              if(result>=5 && lastAirlineCount==result){
                display(
                  `Airline ${cutAddress(address)}`,
                  'Register Airline', [{
                    label: cutAddress(airlineToBeAdded),
                    error: error,
                    value: `${votes} more vote(s) required`
                  }]
                )
              }
            });

          });

          DOM.elid('buy').addEventListener('click', async () => {
            let input = DOM.elid('buyFlight').value
            input = input.split('-')
            input = input.map(el => { return el.trim() })
            const index = input[0]
            const insurance = DOM.elid('buyAmount').value

            // Fetch args from server
            fetch('http://localhost:3000/flights')
              .then(res => { return res.json() })
              .then(flights => {
                return flights.filter(el => { return el.index == index })
              })
              .then(async flight => {
                const { flight: { flightNo, to, landing, price } } = flight[0]

                const { passenger, error } = await contract.buy(
                  flightNo,
                  to,
                  landing,
                  price / 1000000000000000000,
                  insurance)
                display(
                  `Passenger ${cutAddress(passenger)}`,
                  'Book flight',
                  [{
                    label: `${flightNo} to ${to} lands at ${landing}`,
                    error: error,
                    value: `insurance: ${insurance} ETH`
                  }]
                )
              })
          })

          DOM.elid('pay').addEventListener('click', () => {
            try {
              contract.withdraw()
            } catch (error) {
              console.log(error.message)
            }
          });

          contract.registerAirlineRegisteredEvent((event) => {
            display('Airline registered', 'Airline data', [ { label: 'Details', error: '', value: ("Airline added: "+ cutAddress(event.returnValues.airlineAddr)+"| Requesting Addres: "+cutAddress(event.returnValues.requestingAirline))} ]);
          });

          contract.countAirlines((result, ownerAdd) => {
            display('Current Airlines', 'Current Airline Count', [ { label: 'Total', error: '', value: result+" counting owner address that is registered at constructor: "+cutAddress(ownerAdd)} ]);
          });

    
    });
    

})();


function display(title, description, results) {
    let displayDiv = DOM.elid("display-wrapper");
    let section = DOM.section();
    section.appendChild(DOM.h2(title));
    section.appendChild(DOM.h5(description));
    results.map((result) => {
        let row = section.appendChild(DOM.div({className:'row'}));
        row.appendChild(DOM.div({className: 'col-sm-4 field'}, result.label));
        row.appendChild(DOM.div({className: 'col-sm-8 field-value'}, result.error ? String(result.error) : String(result.value)));
        section.appendChild(row);
    })
    displayDiv.append(section);

}

function cutAddress (address) {
    return `${address.slice(0, 5)}...${address.slice(-3)}`
}

function parseDate(dateNum) {
  return new Date(dateNum).toString().slice(0, -42)
}







