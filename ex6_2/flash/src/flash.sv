// The Flash Navigator
// Let's get straight into developing the flash navigator. To begin with we won't worry about the navigation part, let us just see we can read 32 bytes of memory from the flash IC.
// Our module needs to receive the wait time for the flash to initialize as a parameter. For inputs / outputs we have the following:
`default_nettype none
module flashNavigator#(
  parameter CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter STARTUP_WAIT_MS = 10 // 
)
(
  input  wire  clk,                // - the 27Mhz main clock signal.
  output reg   flashClk  = 0,      // - the SPI clock for the flash IC.
  input  wire  flashMiso,          // - the SPI data in from the flash to the tang nano.
  output reg   flashMosi = 0,      // - the SPI data out from the tang nano to flash.
  output reg   flashCs   = 1,      // - the SPI chip select, active low.
  input  wire [5:0] charAddress,   // - the current char to display to the screen (used to interface with the text engine). Value 0-63 (screen is dissected to 16x4 chars)
  output reg  [7:0] charOutput = 0, // - the character in ASCII format that we want to be displayed at 'charAddress'. Note that, to depict a byte , we need two ASCII chars 
  input  wire  btn1, // - button S1 on the Tang nano board
  input  wire  btn2  // - button S2 on the Tang nano board
);
// For all the outputs we add the 'reg' keyword to make it auto generate an output register connected to those wires. Next we can create some registers:

reg  [23:0] readAddress    = 0;     // - is a register to store the 24-bit address we want to read from flash, 
reg   [7:0] command        = 8'h03; // - stores the command we want to send the flash IC, 03 is the READ command as we saw in the datasheet.
reg   [7:0] currentByteOut = 0; // - a register to store the current data byte from flash as ...
reg   [7:0] currentByteNum = 0; // -  ... well as a counter to count which byte we are on from the 32 bytes we want to read
reg [255:0] dataIn         = 0; // - Finally we have two buffers which are 256 bits long or 32 bytes to hold ... - this will be constantly updated with each received bit
reg [255:0] dataInBuffer   = 0; // ... a single read operation of 32 bytes. - this will be updated all at once, when we have received a full (32 byte) frame.

// The reason we have a separate register for the entire 32 bytes and a separate register for the current byte is just because it sends each byte MSb first, 
// but the bytes come least significant byte (LSB) first so they have apposing directions if we wanted to shift the data in. We would have to jump 8 bits forward 
// and then backtrack when updating the memory which would make the code more complex.

// So by separating them we can shift the current byte in by shifting the MSB left and then just add it to the 'dataIn' register which stores the entire frame.

// Note: A byte consits of two 4-bit nibbles, i.e. a hex value "FE", consits of and needs two ASCII chars (two bytes) to depict it. So, remember that.

// The reason we have two buffers for the current frame is so that one will be controlled by the reading code and one will be used by the other components consuming the data. 
// This way we don't have to synchronize between them we simply read bits into 'dataIn' and only when we have a complete frame we update 'dataInBuffer' all at once so components
// consuming the data always have an up to date frame they can read from.

// Next our flash navigator module will have the following states to perform the read sequence:
localparam STATE_INIT_POWER           = 8'd0; // We will wait for the IC to initialize, ... 
localparam STATE_LOAD_CMD_TO_SEND     = 8'd1; // ... then load the command we want to send, ...
localparam STATE_SEND                 = 8'd2; // ... we can then send the command in the state.
localparam STATE_LOAD_ADDRESS_TO_SEND = 8'd3; // Afterwards, send the address, this can be done by loading the address and reusing the same STATE_SEND
localparam STATE_READ_DATA            = 8'd4; // After sending both the command to read and address we want, we need to read 32 bytes out,
localparam STATE_DONE                 = 8'd5; // Once all 32 bytes are read we will go to the done state and transfer our 'dataIn' register into 'dataInBuffer'.

// To accomplish this we will need a few more registers:
reg [23:0] dataToSend = 0; // a common register which we can store either the command or address,  then the send state only needs to send from here.
reg  [8:0] bitsToSend = 0; // the number of bits we want to send - commands are only 8 bits and addresses 24 bits, we have to know how many we want each time we are sending data.
localparam STARTUP_WAIT_CYCL = ((27000000/1000)*STARTUP_WAIT_MS);
reg [32:0] clkCounter = 0; // general purpose (clk) counter register we will use in our state machine,
reg  [2:0] state = 0; // stores our current FSM state
reg  [2:0] returnState = 0;  // for setting the state to return to after sending data - because we are using the send state for two different parts of the read sequence,
                             // so we have to know where to return to.
reg dataReady = 0; // flag - once we have finished reading all 32 bytes to tell other parts of the module when it can use the data.

// We have 6 states in-order to implement the full read sequence, SPI here is communicating in both directions:
// we have to send the command and address and then read data back from the flash chip.
always_ff @(posedge clk) begin 
  case(state) 
    STATE_INIT_POWER: begin  // The Power Initialization State
      if(clkCounter > STARTUP_WAIT_CYCL && btn1==1 && btn2==1) begin // also debounce on the buttons so that the loading will only happen on the release of the button so it doesn't scroll hundreds of times a second in a single button press.
        clkCounter <= 32'b0;
        currentByteNum <= 0;
        currentByteOut <= 0; 
        state <= STATE_LOAD_CMD_TO_SEND;
      end else begin 
        clkCounter <= clkCounter + 1;
      end
    end 
    STATE_LOAD_CMD_TO_SEND: begin // The Load Command State
      flashCs <= 0; // set the CS pin to activate the Flash chip (active-low), as we're about to start sending data
      dataToSend[23-:8] <= command; // load the command into the send buffer. Note: Put the command at the top 8 bits instead of the bottom 8 bits from the 24-bit dataToSend register. 
                                    // This is because with this flash chip we are sending MSB first so by putting it at the top 8 bits we can easily shift them off the end.
      bitsToSend <= 8; // set the number of bits to send to 8 since our command is 8 bits,
      returnState <= STATE_LOAD_ADDRESS_TO_SEND; // sets the return state after sending data to be load address state 
      state <= STATE_SEND; // and move onto the send state
    end 
    STATE_SEND: begin // The Send State 
      if(clkCounter == 32'd0) begin // splitting our main clock into two SPI clocks - generate the SPI clock falling edge
        flashClk <= 0; // when the 'clkCounter' is 0 we create SPI clock falling-edge, so we change (shfit data out) the MOSI pin on 
        flashMosi <= dataToSend[23]; //  we set the output pin to be the most significant bit (MSb) of 'dataToSend' and ... 
        dataToSend <= {dataToSend[22:0],1'b0}; // ... then we shift dataToSend one bit to the left since we already handled the last bit. 
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
      dataToSend <= readAddress; // load address register, which is 24 bits long,
      bitsToSend <= 24; 
      currentByteNum <= 0;
      returnState <= STATE_READ_DATA;
      state <= STATE_SEND;
    end 
    STATE_READ_DATA: begin 
      if(clkCounter[0] == 1'd0) begin 
        flashClk <= 0; //  // here we also split our clock into one cycle for the falling edge
        clkCounter <= clkCounter + 1;
        if((clkCounter[3:0] == 0) && (clkCounter > 0)) begin // Each 16 clkCounts = 8-bits (one byte) had been latched from Flash IC, we need to be able to count each time we have read 8 bits.  
          dataIn[(currentByteNum << 3)+:8] <= currentByteOut; // But the incomming data bytes themselves, are arranged/coming least significant byte (LSB) first, (or at least lowest address first).
          currentByteNum <= currentByteNum + 1;
          if(currentByteNum == 31) // If we've received all 32 data bytes from the Flash IC ...
            state <= STATE_DONE; // ... move onto the next state - DONE state
        end 
      end else begin 
        flashClk <= 1; // here we also split our clock into one cycle for the rising edge, letting the flash chip read the data we set.
        clkCounter <= clkCounter + 1;
        currentByteOut <= {currentByteOut[6:0], flashMiso}; // Shift-in (latch) the incomming data bits (of each Data Byte) coming from the Flash IC - MSb first. 
                                                            // The bits of data bytes come Most Significant bit first. So we shift left, so that after 8 shifts the first bit we put in will be the most significant bit.
      end 
    end
    // Navigating the Flash
    // We have already passed in our buttons into the module, so all we really need to do is let our buttons control which address we are reading, this can be done with two small changes here.
    STATE_DONE: begin // The Done State
      dataReady <= 1; // indicate that we're done - acquired (read) all 32 data bytes from the Flash IC
      flashCs <= 1; // de-assert the Chip-Select of the Flash IC, stopping the read operation 
      dataInBuffer <= dataIn; // we copy all the acquired 32-byte data read from 'dataIn' to 'dataInBuffer'.
      clkCounter <= STARTUP_WAIT_CYCL; // We also reset counter to be the startup delay and ...
      // We are advancing the counter by 24 bytes each time and not 32 like we are displaying because we want to only display data on the top 3 lines and use the final line to display the current address.
      if(btn1 == 0) begin  // if the first button is pressed ...
        readAddress <= readAddress + 24; // ... we increment the read address by 24 and ...
        state <= STATE_INIT_POWER; // ... go back to the init state to restart the read process at the new address
      end else if(btn2 == 0) begin
        readAddress <= readAddress - 24; // ...  we will decrement the readAddress
        state <= STATE_INIT_POWER; // ... go back to the first state to repeat the cycle but this time without a delay.
      end
    end
  endcase 
end
// With that we should now be able to read the first 32 bytes of memory.

// We can then add the following to our flashNavigator module to display the data:
reg   [7:0] chosenByte = 0; // - will store the current byte we want to display from the 32 different bytes we have read from memory.
wire  [7:0] byteDisplayNumber; // - will be the index of the byte we want so again this can be from 0-31.
wire  lowerBit; // - Each byte is represented by 2 hex characters so we need to know if we are on the first or, second character which we do with 'lowerBit' 
wire  [7:0] hexCharOutput; // - will store the ASCII value we get back from the hex conversion
wire  [3:0] currentHexVal; // - will store the 4 bits we are currently want to convert.

assign byteDisplayNumber = charAddress[5:1]; // 'charAddress' holds the (current) cursor index of the display, in ASCII Chars - value 0 to 63 . As every byte consists of two chars, we divide by two - removing the smallest bit.
assign lowerBit = charAddress[0]; // ... a d we put the smallest bit, to indicate whether we're on the first or the second character of the byte value.
assign currentHexVal = lowerBit ? chosenByte[3:0] :  chosenByte[7:4] ;// whether or not we are on the higher half or lower half of the byte, we take the corresponding 4 bits out of the 8 bit byte 'chosenByte'

// Creates an instance of our hex converter with the current 4-bits we want to convert and it will output the result to hexCharOutput.
toHex hexConvert(
  .clk(clk), // input clock the module
  .value(currentHexVal), // input 4-bit hex value (0x0 - 0xF) we want to display
  .hexChar(hexCharOutput) // output 8-bit ASCII character value, equivalent.  
);

// Displaying the Current Address
// We have a 24 bit address if we wanted to display it in HEX format we would need 6 hex characters. We could create 6 registers and 6 toHex modules one for each of the characters of the address manually, but verilog 
// has a feature for situations like this where we can "generate" repetitive code in a sort of for loop:
genvar i; 
generate 
  for(i = 0; i < 6; i = i+1) begin: addr
    wire [7:0] hexChar;
    toHex hexConv(
      .clk(clk), // input clock the module
      .value(readAddress[{i,2'b0}+:4]), // input 4-bit hex value (0x0 - 0xF) we want to display
      .hexChar(hexChar) // output 8-bit ASCII character value, equivalent.  
    );
  end
endgenerate
// In our loop we are iterating 6 times, each time creating an 8 bit wire to reference the ASCII output from the hex conversion, and then we send the appropriate bits from readAddress to the conversion module.
// You can also see on the line with the 'for' loop we end the line with a colon (:) and a word 'addr' this word is the name we are giving this block. We can name the block whatever we like just like other variables and
// it gives us a way to reference the variables instantiated inside. So for example if we want to access 'hexChar' from the third iteration we can write 'addr[2].hexChar' to reference it.

// The only thing we have left to do is to put the current data we want to convert into 'chosenByte' and output 'hexCharOutput' back to the text engine to convert to pixel data.
// We can then change the always block to output a special address line on the 4th row:
always_ff @(posedge clk) begin 
  chosenByte <= dataInBuffer[(byteDisplayNumber << 3)+:8]; // put the current data we want to convert
  if(charAddress[5:4] == 2'b11) begin 
    case(charAddress[3:0])
      0: charOutput <= "A";
      1: charOutput <= "d";
      2: charOutput <= "d";
      3: charOutput <= "r"; 
      4: charOutput <= ":";
      // 5: is missing, it will be " " covered by the 'default:' statement
      6: charOutput <= "0";
      7: charOutput <= "x";
      8: charOutput <= addr[5].hexChar;
      9: charOutput <= addr[4].hexChar;
      10: charOutput <= addr[3].hexChar;
      11: charOutput <= addr[2].hexChar;
      12: charOutput <= addr[1].hexChar;
      13: charOutput <= addr[0].hexChar;
      // 14: is missing, it will be " " covered by the 'default:' statement
      15: charOutput <= dataReady ? " " : "L";
      default: charOutput <= " ";
    endcase
  end else begin   
    charOutput <= hexCharOutput;  // output back to the text engine to convert to pixel (byte) data
  end
end
// The first line stayed the same, then we check if we are on the 4th line or not. If so we output specific characters for each of the 16 characters in this row to spell out "Addr: 0x<addr>". We also added an "L" 
// in the last position while loading, not that you will really be able to see it as it is super fast.
// We don't really need to check the 'dataReady' flag since we have a double buffer for the input data we always have a valid frame which we can display while the read sequence continues to update the other register.

// We should now have a complete module which allows us to load the first 32 bytes and display them to the screen. To test it though we need to do a bit of setup.
endmodule

// Displaying The Data
// Having the data read is nice, but we need to be able to see it to believe it. So let's add to the same flashNavigator module some code to output the data in hex format to the screen.
// Hex is almost as easy as binary, since hex is base 16 which is also a power of 2 like binary, it means that every four bits translate to exactly one hex character. So to display our 8-bit number we need exactly 2 hex characters. 
// The conversion for each hex character is also pretty simple, with 4-bits we can have a maximum value of 15, for 0-9 we simply put that same digit as the output in ascii, and from 10-15 we move to letters A-F.
module toHex(
  input wire clk,
  input wire [3:0] value, // we receive the 4-bit number which ...
  output reg[7:0] hexChar = "0" // ... we need to convert to an ASCII letter.
);

always_ff @(posedge clk) begin 
  hexChar <= (value <= 9) ? "0" + value : ("A" - 10) + value;
end
endmodule // toHex 
