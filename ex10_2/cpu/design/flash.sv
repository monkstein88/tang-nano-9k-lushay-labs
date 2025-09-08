// < Some Prerequisties > 

// We will also need a module to read our code. We will be storing our code in the external flash, as it is easy to program, but that means we need a way to load a specific byte from flash. For this we can repurpose our 
// flash module which we created originally created - 'flash.v'.
// The main change we need to make there, it is to use to read a whole "page" of bytes and we only want it to read a single byte.
// Here is the module after the changes:

`default_nettype none
module flash#(
  parameter CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter STARTUP_WAIT_MS = 10 // 
)
(
  input  wire        clk,               // - the 27Mhz main clock signal.
  output reg         flashClk  = 0,     // - the SPI clock for the flash IC. (idle/init low)
  input  wire        flashMiso,         // - the SPI data in from the flash to the tang nano. 
  output reg         flashMosi = 0,     // - the SPI data out from the tang nano to flash. (idle/init low)
  output reg         flashCs   = 1,     // - the SPI chip select, active low. (idle/init high)
  input  wire [10:0] addr,              // - address set to the FLASH memory to read from/write to.
  output reg  [7:0]  byteRead = 0,      // - byte value read from the FLASH memory
  input  wire        enable,            // - used to start the data read from FLASH memory
  output reg         dataReady = 0      // - flag once we have finished reading all 32 bytes to tell other parts of the module when it can use the data.
);

reg   [7:0] command        = 8'h03; // - stores the command we want to send the flash IC, 03 is the READ command as we saw in the datasheet.
reg   [7:0] currentByteOut = 0; // - a register to store the current data byte from flash as ...

// Next our flash access module will have the following states to perform the read sequence:
localparam STATE_INIT_POWER           = 8'd0; // We will wait for the IC to initialize, ... 
localparam STATE_LOAD_CMD_TO_SEND     = 8'd1; // ... then load the command we want to send, ...
localparam STATE_SEND                 = 8'd2; // ... we can then send the command in the state.
localparam STATE_LOAD_ADDRESS_TO_SEND = 8'd3; // Afterwards, send the address, this can be done by loading the address and reusing the same STATE_SEND
localparam STATE_READ_DATA            = 8'd4; // After sending both the command to read and address we want, we need to read 1 byte out,
localparam STATE_DONE                 = 8'd5; // Once the byte is read we will go to the done state and transfer our 'dataIn' register into 'dataInBuffer'.

// To accomplish this we will need a few more registers:
reg [23:0] dataToSend = 0; // a common register which we can store either the command or address,  then the send state only needs to send from here.
reg  [8:0] bitsToSend = 0; // the number of bits we want to send - commands are only 8 bits and addresses 24 bits, we have to know how many we want each time we are sending data.
localparam STARTUP_WAIT_CYCL = ((27000000/1000)*STARTUP_WAIT_MS);
reg [32:0] clkCounter = 0; // general purpose (clk) counter register we will use in our state machine,
reg  [2:0] state = 0; // stores our current FSM state
reg  [2:0] returnState = 0;  // for setting the state to return to after sending data - because we are using the send state for two different parts of the read sequence,
                             // so we have to know where to return to.

// We have 6 states in-order to implement the full read sequence, SPI here is communicating in both directions:
// we have to send the command and address and then read data back from the flash chip.
always_ff @(posedge clk) begin 
  case(state) 
    STATE_INIT_POWER: begin  // The Power Initialization State
      if(clkCounter < STARTUP_WAIT_CYCL)  
        clkCounter <= clkCounter + 1;
      else if(enable) begin
        clkCounter <= 0;
        dataReady <= 0;
        currentByteOut <= 0; 
        state <= STATE_LOAD_CMD_TO_SEND;
      end
    end 
    STATE_LOAD_CMD_TO_SEND: begin // The Load Command State
      flashCs <= 0; // set the CS pin to activate the Flash chip (active-low), as we're about to start sending data
      dataToSend[23-:8] <= command; // load the command into the send buffer. Note: Put the command at the top 8 bits instead of the bottom 8 bits from the 24-bit 'dataToSend' register. 
                                    // This is because with this flash chip we are sending MSB first so by putting it at the top 8 bits we can easily shift them off the end.
      bitsToSend <= 8; // set the number of bits to send to 8 since our command is 8 bits,
      returnState <= STATE_LOAD_ADDRESS_TO_SEND; // sets the return state after sending data to be load address state 
      state <= STATE_SEND; // and move onto the send state
    end 
    STATE_SEND: begin // The Send State 
      if(clkCounter == 32'd0) begin // splitting our main clock into two SPI clocks - generate the SPI clock falling edge
        flashClk <= 0; // when the 'clkCounter' is 0 we create SPI clock falling-edge, so we change (shfit data out) the MOSI pin on 
        flashMosi <= dataToSend[23]; //  we set the output pin to be the most significant bit (MSb) of 'dataToSend' and ... 
        dataToSend <= {dataToSend[22:0],1'b0}; // ... then we shift 'dataToSend' one bit to the left since we already handled the last bit. 
        bitsToSend <= bitsToSend - 1; // also decrement bitsToSend and ... 
        clkCounter <= 1; // ... set the counter to 1 so we can move onto the rising edge in the next clock cycle.
      end else begin // splitting our main clock into two SPI clocks - generate the SPI clock rising edge
        flashClk <= 1; // when the 'clkCounter' is 1 we create SPI clock rising-edge - we latch (shit data in) the MISO pin on SPI clock rising edge.
        clkCounter <= 32'd0;     
        if(bitsToSend == 0) //  checking if this was the last bit ...
          state <= returnState; // ... in which case we move onto the next state which was stored in returnState
      end
    end 
    STATE_LOAD_ADDRESS_TO_SEND: begin // The Load Address State 
      dataToSend <= {13'b0, addr}; // load address register, which is 24 bits long,
      bitsToSend <= 24; 
      returnState <= STATE_READ_DATA;
      state <= STATE_SEND;
    end 
    STATE_READ_DATA: begin 
      if(clkCounter[0] == 1'd0) begin 
        flashClk <= 0; // here we also split our clock into one cycle for the falling edge
        clkCounter <= clkCounter + 1;
        if((clkCounter[3:0] == 0) && (clkCounter > 0)) begin // Each 16 clkCounts = 8-bits (one byte) had been latched from Flash IC, we need to be able to count each time we have read 8 bits.  
          byteRead <= currentByteOut; // But the incomming data bytes themselves, are arranged/coming least significant byte (LSB) first, (or at least lowest address first).
          state <= STATE_DONE; // ... move onto the next state - DONE state
        end 
      end else begin 
        flashClk <= 1; // here we also split our clock into one cycle for the rising edge, letting the flash chip read the data we set.
        clkCounter <= clkCounter + 1;
        currentByteOut <= {currentByteOut[6:0], flashMiso}; // Shift-in (latch) the incomming data bits (of each Data Byte) coming from the Flash IC - MSb first. 
                                                            // The bits of data bytes come Most Significant bit first. So we shift left, so that after 8 shifts the first bit we put in will be the most significant bit.
      end 
    end
    STATE_DONE: begin // The Done State
      dataReady <= 1; // indicate that we're done - acquired (read) all 32 data bytes from the Flash IC
      flashCs <= 1; // de-assert the Chip-Select of the Flash IC, stopping the read operation 
      clkCounter <= STARTUP_WAIT_CYCL; // We also reset counter to be the startup delay and ...
      if(~enable) begin  // if the enable is not ..
        state <= STATE_INIT_POWER; // ... go back to the init state to restart the read process at the new address
      end
    end
  endcase 
end
// With that we should now be able to read a byte from flash memory.

endmodule // flash

