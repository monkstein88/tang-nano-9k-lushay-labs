`default_nettype none 

module uart
#(
  parameter DELAY_FRAMES = 234 // 27 [Mhz] / 115200 [Baud-rate]
)
(
  input wire EXT_CLK,
  input wire BTN_S1,
  input wire UART_RX,
  output reg UART_TX=1, // Default to high
  output reg [5:0] LED_O=6'b111111 // Default to all high - LEDs are active low
);

localparam HALF_DELAY_WAIT = (DELAY_FRAMES/2);

/* ======================================= UART Receiver (RX) Part ========================================== */
/* UART is set for 115200 baud/s - 8N1 config */
reg[3:0] rxState = 0; // Hold in-which state we're currently in.
reg[12:0] rxCounter = 0; // needed to count clk pulses (234 clk pulses =  1 UART bit frame) 
reg[2:0] rxBitNumber = 0; // to keep track of how many bits we have read so far, thus know when data is finished and stop bit is to be expected
reg[7:0] dataIn = 0; // This is an 8-bit register that will store the received byte
reg byteReady = 0; // Flag register that will tell us when we have finished reading a byte, and dataIn is valid to use.

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
always @(posedge EXT_CLK) begin 
  case(rxState)
    RX_STATE_IDLE: begin 
      if(UART_RX == 0) begin // The START BIT had come - pulls the uart rx line low (GND)
        rxState <= RX_STATE_START_BIT;
        rxCounter <= 1;
        rxBitNumber <= 0;
        byteReady <= 0;
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
      dataIn <= {UART_RX, dataIn[7:1]}; // Shift in bits - from MSb side, to end up to be the LSb side.
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

/* Let's add an always block that will reacto the data being received and ready - UART_RX and display 
 * the data (or 6 LSb of it at least) on the leds */
 always @(posedge EXT_CLK) begin 
  if(byteReady) begin 
    LED_O <= ~dataIn[5:0]; // Note: we're inverting because the LEDs light up when a bit is set low.
  end
 end 

/* ======================================= UART Transmitter (TX) Part ========================================== */
// The transmit side is very similar to the implementation of the receiver we did above, except that we don't 
// want to count from the middle of the pulse, the transmit side has to change the line at the beginning of each 
// bit frame.
reg[3:0]  txState = 0; // Keep track of the UART TX state machine
reg[24:0] txCounter = 0; // Count the number of 'EXT_CLK' cycles
reg[7:0]  dataOut = 0; // will store the byte being sent currently
reg [2:0] txBitNumber = 0; // Keep track of which bit we're currently sending
reg [3:0] txByteCounter = 0; // and for which byte

// In our example we will be sending a message from memory, so we need to keep track of the current byte.  
// and the last two lines define a new "memory" where each cell is 8 bits long, and in our example we have
// 12 total cells.
localparam MEMORY_LENGTH = 12;
reg[7:0] testMemory [MEMORY_LENGTH-1:0];

// This next code initializes ... 
initial begin 
  UART_TX = 1; // ... start with the UART TX line high - idle state
  LED_O = 6'b111111; // ... start with all LEDs turned off (active low) - idle state
  
  // ... the memory with the message we want to send.
  testMemory[0] = "L";
  testMemory[1] = "u";
  testMemory[2] = "s";
  testMemory[3] = "h";
  testMemory[4] = "a";
  testMemory[5] = "y";
  testMemory[6] = " ";
  testMemory[7] = "L";
  testMemory[8] = "a";
  testMemory[9] = "b";
  testMemory[10] = "s"; 
  testMemory[11] = " ";
end 

// Next let's define the states of our state machine. We don't have an extra "wait" stage here, again because we are
// not offsetting to the middle of the frame like when reading. We do have an extra stage at 
// the end to debounce the button, since we will be using the button to determine when to send data.
localparam TX_STATE_IDLE = 0;
localparam TX_STATE_START_BIT = 1;
localparam TX_STATE_WRITE = 2;
localparam TX_STATE_STOP_BIT = 3;
localparam TX_STATE_DEBOUNCE = 4;

always @(posedge EXT_CLK) begin 
  case(txState)
    TX_STATE_IDLE: begin 
      if(BTN_S1 == 0) begin // Wait till the button is pressed (active-low) ...
        txState <= TX_STATE_START_BIT;  // If so , head to the next state - START BIT state
        txCounter <= 0;
        txByteCounter <= 0;
      end 
      else begin 
        UART_TX <= 1; // Otherwise, keep the uart tx line high - idle state
      end
    end
    TX_STATE_START_BIT: begin 
      UART_TX <= 0; // So we begin transmitting - by pullint UART TX pin low - START BIT - ...
      if((txCounter + 1) == DELAY_FRAMES) begin // ... for DELAY_FRAMES amount of time, once reached....
        txState <= TX_STATE_WRITE;
        dataOut <= testMemory[txByteCounter]; // we put the the next byte we need to send into and ...
        txBitNumber <= 0; // ... reset the bit counter back to 0.
        txCounter <= 0;
      end else 
        txCounter <= txCounter + 1;
    end 
    TX_STATE_WRITE: begin 
      UART_TX <= dataOut[txBitNumber]; // Now, after START BIT expired, now apply bit #0 of the data to uart_tx pin, 
      if((txCounter+1) == DELAY_FRAMES) begin  // When the frame is over, we check ...
        if(txBitNumber == 3'b111) begin  // ... if we are at the last bit, if so ...
          txState <= TX_STATE_STOP_BIT; // ... go to the stop bit state. 
        end else begin  // Otherwise, ...
          txState <= TX_STATE_WRITE; // keep in the current state and ... 
          txBitNumber <= txBitNumber + 1;  // ... and iterate (increment) over each bit of the data byte
        end 
        txCounter <= 0;
      end else 
        txCounter <= txCounter + 1;
    end
    TX_STATE_STOP_BIT: begin 
      UART_TX <= 1; // Signal the STOP BIT - keeping the uart-tx pin high ...
      if((txCounter+1) == DELAY_FRAMES) begin  // ... for the DELAY_FRAMES time. 
        if(txByteCounter == MEMORY_LENGTH - 1) begin  // Then, check if there any other bytes to send ...
          txState <= TX_STATE_DEBOUNCE; // ... if there are no pending bytes, go to debounce state. 
        end else begin 
          txByteCounter <= txByteCounter + 1; // ... if there pending bytes, we go back to send another START BIT
          txState <= TX_STATE_START_BIT; // ... and repeat the cycle.
        end 
        txCounter <= 0; 
      end else 
        txCounter <= txCounter + 1;
    end 
    TX_STATE_DEBOUNCE: begin  // Here we're just waiting a minimum time (about 10 [ms]) on top of the sending time, ...
      if(txCounter == 23'b111111111111111111) begin 
        if(BTN_S1 == 1) begin // ... and making sure the button is released after this time - unpressed = HIGH. To ensure a single press makes one transmission
          txState <= TX_STATE_IDLE;
          txCounter <= 0;
        end
      end else 
        txCounter = txCounter + 1;
    end 
  endcase
end

endmodule