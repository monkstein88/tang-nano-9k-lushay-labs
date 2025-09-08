// Preparing The Project
// There are a few changes that we need to make to the UART and Text Engine components to use them in this project. For the UART we can delete all the transmitter stuff and expose the data and 'byteReady' flag via output parameters:

`default_nettype none 

module uart
#(
  parameter DELAY_FRAMES = 234 // 27 [Mhz] / 115200 [Baud-rate]
)
(
  input wire clk,
  input wire uartRx, 
  output reg byteReady,  // Flag register that will tell us when we have finished reading a byte, and dataIn is valid to use.
  output reg [7:0] dataIn  // This is an 8-bit register that will store the received byte
);

localparam HALF_DELAY_WAIT = (DELAY_FRAMES/2);

/* ======================================= UART Receiver (RX) Part ========================================== */
/* UART is set for 115200 baud/s - 8N1 config */
reg[3:0] rxState = 0; // Hold in-which state we're currently in.
reg[12:0] rxCounter = 0; // needed to count clk pulses (234 clk pulses =  1 UART bit frame) 
reg[2:0] rxBitNumber = 0; // to keep track of how many bits we have read so far, thus know when data is finished and stop bit is to be expected

/* Lets' define the states of our state machine
 * That way we can start in an "idle" state when we see the start bit we can start receiving data 
 * and go to the "read data" state and then once we finish the bit we can go to the "stop bit" 
 * state finally returning back to "idle" ready to receive the next communication. */
localparam RX_STATE_IDLE = 0;
localparam RX_STATE_START_BIT = 1;
localparam RX_STATE_READ_WAIT = 2;
localparam RX_STATE_READ = 3;
localparam RX_STATE_STOP_BIT = 5;

/* Like mentioned above, we start in an idle stage, when there is a start bit we need to wait a certain amount of time, 
 * then 8 times we can alternate between reading a bit, and waiting for the next bit. Finally we have a state for the 
 * stop bit so we can again wait for it to complete and go back to being idle. */
always_ff @(posedge clk) begin 
  case(rxState)
    RX_STATE_IDLE: begin 
      byteReady <= 0;
      if(uartRx == 0) begin // The START BIT had come - pulls the uart rx line low (GND)
        rxState <= RX_STATE_START_BIT;
        rxCounter <= 1;
        rxBitNumber <= 0;
      end 
    end
    RX_STATE_START_BIT: begin // We're at the beginning of a START BIT, so wait for half bit time
      if(rxCounter == HALF_DELAY_WAIT) begin 
        rxState <= RX_STATE_READ_WAIT; 
        rxCounter <= 1;
      end else 
        rxCounter <= rxCounter + 1;
    end 
    RX_STATE_READ_WAIT: begin // Now, we're in the middle of the START BIT, wait for a whole bit time
      rxCounter <= rxCounter + 1; 
      if((rxCounter + 1) == DELAY_FRAMES) begin 
        rxState <= RX_STATE_READ;
      end
    end
    RX_STATE_READ: begin // Now, we're in the middle of a DATA BIT, store that as DATA and iterate
      rxCounter <= 1;
      dataIn <= {uartRx, dataIn[7:1]}; // Shift in bits - from MSb side, to end up to be the LSb side.
      rxBitNumber <= rxBitNumber + 1;
      if(rxBitNumber == 3'b111) 
        rxState <= RX_STATE_STOP_BIT;
      else
        rxState <= RX_STATE_READ_WAIT;  
    end 
      RX_STATE_STOP_BIT: begin  // Now, we're in the middle of a STOP BIT, so wait & go back to IDLE state
        rxCounter <= rxCounter + 1;
        if((rxCounter + 1) == DELAY_FRAMES) begin // wait for a whole BIT TIME, and we can jump back to IDLE state.
          rxState <= RX_STATE_IDLE; 
          rxCounter <= 0; 
          byteReady <= 1; 
        end 
      end 
  endcase 
end 

endmodule