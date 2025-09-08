`resetall // Resets all compiler directives at the beginning of each module or file to avoid 
          // unintended side effects from previous directives. 

module screen
#(
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT = 32'd1000000 // delay for power-up initialization
)
(
  input wire EXT_CLK,  // This is the external clock source on the board - expected 27 [MHz] oscillator. 
  input wire BTN_S1, // This pin is tied to a button 'S1' on the board, and will be used as a 'reset' source (active-low) 
  input wire BTN_S2, // This pin is tied to a button 'S2' on the board, and will be used as a general user input source (active-low) 
  output reg [5:0] LED_O, // 6 Orange LEDs on the board, active-low 
  // LCD 0.96" SPI interface - SSD1306 controller
  output wire LCD_SPI_RST, // reset: active-low  
  output wire LCD_SPI_CS, // chip-select: active-low Note: multiple bytes can be sent without needing to change the chip select each time.
  output wire LCD_SPI_SCLK, // spi clock signal: idle-low 
  output wire LCD_SPI_DIN, // data input. Note: data is latched on the rising edge of the clock and is updated on the falling edge. MSb is sent first.
  output wire LCD_SPI_DC  // data/command select: active-low - data, active-high - command
);

/*
  So our state machine will have the following steps:
  1.Power Initialization Wait / Reset
  2.Load Init Command Byte
  3.Send Byte over SPI
  4.Check Where to go from Sending
  5.Load Pixel Data Byte

  Note: Technically the next state would be to send the command byte over SPI, but there is no real 
  difference between sending a command byte or sending a pixel byte so state 3 can be used for both.
  The only difference is which state to go to after sending the byte. In the case where there are more
  commands to send we would like to go to the state to load the next command otherwise we want to go to 
  the state to load the next pixel byte. So step 4 will just check if there are more commandsand if so
  go back to step 2 otherwise go to step 5. And step 5 just loads a pixel byte and links back to send 
  it with step 3.
*/
localparam  STATE_INIT_POWER = 8'd0; // Power Initialization Wait / Reset
localparam  STATE_LOAD_INIT_CMD = 8'd1; // Load the init command byte
localparam  STATE_SEND_BYTE = 8'd2; // Send the byte over SPI
localparam  STATE_CHECK_NEXT = 8'd3; // Check if there are more commands to send, or, if we are sending pixel data
localparam  STATE_LOAD_PIXEL = 8'd4; // Load the pixel data byte

reg [32:0] counter = 0; // 33-bit clk counter for the wait state 
reg [2:0] state = STATE_INIT_POWER; // 3-bit state machine - for our 5 states

/* Register for each of the LCD inputs to drive them */
reg dc = 1; // default to command (could have chosen either)
reg sclk = 1; // idle-high
reg sdin = 0; // idle-low
reg reset = 1; // default/idle - de-asserted (high)
reg cs = 1; // default/idle de-asserted (high)

reg [7:0] dataToSend = 0; // register for the current byte we will be sending - 8-bit data to send over SPI 
reg [3:0] bitNumber = 0; // register to remember which bit of the current byte we are on of the 'dataToSend'
reg [9:0] pixelCounter = 0; // register to keep track of which pixel of the screen we are on

// In terms of Verilog, loading an image instead of our two static rows of lines is pretty easy. We first need 
// a memory where we can store all our bytes: (note the "image.hex file" is in the same dir where this .sv file is)
reg [7:0] screenBuffer [1023:0];
initial $readmemh("image.hex", screenBuffer); // This will hold the text "Lushay Labs"
// Our memory has 1024 slots each of which hold a single byte. The second lines tells the toolchain to load a file 
// called image.hex into this memory.

/*
 Next let's create a register for holding all the init command bytes. We have a total of 16 init commands 
 which take up a total of 25 bytes (some of the commands are 2 bytes).
*/
localparam SETUP_COMMANDS = 25; // number of init commands
reg [7:0] setupCommands [0:SETUP_COMMANDS-1] = { // array of init commands
  8'hAE, // Display OFF
  8'hD5, 8'h80, // Set Display Clock Divide Ratio / Oscillator Frequency: 0x80 (default)
  8'hA8, 8'h3F, // Set Multiplex Ratio: 63 (64 - 1)
  8'hD3, 8'h00, // Set Display Offset: 0 (no offset)
  8'h40, // Set Display Start Line: 0 (start at 0)
  8'h8D, 8'h14, // Charge Pump Setting: Enable Charge Pump
  8'h20, 8'h00, // Set Memory Addressing Mode: Horizontal Addressing Mode
  8'hA1, // Set Segment Re-map: address 0 is segment 0
  8'hC8, // Set COM Output Scan Direction: Noral Scan Direction
  8'hDA, 8'h12, // Set COM Pins Hardware Configuration: Alternative COM pin configuration (disable left/right remap, 128×64=0x12)
  8'h81, 8'h7F, // Set Contrast Value: 0x7F (according to the datasheet)
  8'hA6, // Set Normal Display Mode (non-inverted)
  8'hD9, 8'h22, // Set Pre-charge Period: switch pre-charge to 0x22
  8'hDB, 8'h20, // Set VCOMH Deselect Level: 0x20
  8'hA4, // Resume to RAM content display
  8'hAF // Turn Display ON
};
// Because the concat operator { and } places the most significant byte first, but also 
// because we have inverted the indexing order, the first byte we write is actually placed 
// at the beginning (0) of the array.
reg [7:0] commandIndex = 0; // register for the current command byte we are sending 

/* 
 Next let's connect all the input wires to the registers we created for them. We could have also added the 
 keyword reg to the input parameters themselves in which case it would have automatically created a register 
 for us, but to make it more pronounced I separated it into two steps.
*/
assign LCD_SPI_RST = reset; // connect the reset wire to the reset register
assign LCD_SPI_CS = cs; // connect the chip select wire to the chip select register
assign LCD_SPI_SCLK = sclk; // connect the spi clock wire to the spi clock register
assign LCD_SPI_DIN = sdin; // connect the data input wire to the data input register
assign LCD_SPI_DC = dc; // connect the data/command select wire to the data/command select register

always_ff @(posedge EXT_CLK) begin : spiTransferFSM
  case(state)
    STATE_INIT_POWER: begin 
      counter <= counter + 1; // increment the counter
      if(counter < STARTUP_WAIT)
        reset <= 1; // keep the reset deasserted
      else if(counter < STARTUP_WAIT*2)
        reset <= 0; // reset the screen, clear any previous state
      else if(counter < STARTUP_WAIT*3)
        reset <= 1; // deassert the reset, to make it ready to receive commands/data
      else begin
        counter <= 32'b0; 
        state <= STATE_LOAD_INIT_CMD; // move to the next state
      end
    end
    STATE_LOAD_INIT_CMD: begin 
      dc <= 0; // we're sending a Command 
      dataToSend <= setupCommands[commandIndex]; // Load the next command from 
      state <= STATE_SEND_BYTE;
      bitNumber <= 3'd7;  // Ref. the datasheet we are sending MSb first in the SPI communication.
      cs <= 0; // Tell the screen we want to communicate with it - active low
      commandIndex <= commandIndex + 1;
    end
    STATE_SEND_BYTE: begin // to simplify implementation: we will just use two of our clock cycles for each bit being sent out - one where the SPI clock will be pulled low and one where the SPI clock will be pulled high.
      if(counter == 32'd0) begin 
        sclk <= 0; // Shift out/Change data - on falling edge
        sdin <= dataToSend[bitNumber];
        counter <= 32'd1;
      end
      else begin 
        counter <= 32'd0;
        sclk <= 1; // Data is sampled (read by the LCD) - on rising edge
        if(bitNumber == 0) // check if we are already on the last bit, if so we go on to the next state, otherwise we decrement the bitNumber
          state <= STATE_CHECK_NEXT;
        else 
          bitNumber <= bitNumber - 1;
      end
    end
    STATE_CHECK_NEXT: begin 
      cs <= 1; // de-assert the Chip-Select
      if(commandIndex == SETUP_COMMANDS)
        state <= STATE_LOAD_PIXEL;
      else 
        state <= STATE_LOAD_INIT_CMD;
    end  
    STATE_LOAD_PIXEL: begin 
      pixelCounter <= pixelCounter + 1;
      cs <= 0; // assert the Chip-Select, to re-enable screen communication
      dc <= 1; // we're sending pixed data
      bitNumber <= 3'd7; // reset the bit number to MSb
      state <= STATE_SEND_BYTE;  // et back to the "send byte" state to send the next pixel byte
      dataToSend <= screenBuffer[pixelCounter];
    end
  endcase
end

/*
  The syntax used here with the minus sign after the MSB tells it that we will not be placing the 
  least significant bit but instead the length.
  Usually we use the syntax [MSB:LSB] to access memory here we are using [MSB-:LEN] there is also 
  the option with the a plus instead of a minus for [LSB+:LEN]
*/
/*
  We never need to reset pixelCounter since there are exactly 1024 bytes which exactly fits into 10 bits,
  so the pixelCounter register will automatically roll-over back to zero on its own.
  Note: (128 x 64 pixel disply = 8192 pixels (bits) in total; or 1024 pixel (bytes) in total)
*/
/*
  Some would say the code is even simpler now. The trouble comes more in how to create the file image.hex. 
  We know each byte needs to represent 8 vertical pixels and we need to scan across the image from the 
  top left in rows of 8 pixels. So the task of loading an image is more a task of converting an image into 
  the format we need in-order to display it. Luckily we can create a simple node.js script to do the
  conversion for us.
*/

endmodule