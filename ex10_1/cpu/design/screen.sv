`resetall // Resets all compiler directives at the beginning of each module or file to avoid 
          // unintended side effects from previous directives. 

module screenDriver
#(
    parameter STARTUP_WAIT = 32'd1000000 // delay for power-up initialization
)
(
  input wire clk,  // This is the external clock source on the board - expected 27 [MHz] oscillator. 
  // LCD 0.96" SPI interface - SSD1306 controller
  output wire ioReset, // reset: active-low  
  output wire ioCs, // chip-select: active-low Note: multiple bytes can be sent without needing to change the chip select each time.
  output wire ioSclk, // spi clock signal: idle-low 
  output wire ioSdin, // data input. Note: data is latched on the rising edge of the clock and is updated on the falling edge. MSb is sent first.
  output wire ioDc,  // data/command select: active-low - data, active-high - command
  // Make it receive&set the data from&to an outside module instead of from 'screenBuffer'
  output wire [9:0] pixelAddress, // pixel (byte) address
  input reg [7:0] pixelData // the desired pixel data for that address
);

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
reg [9:0] pixelCounter = 0; // register to keep track of which pixel byte of the screen we are on (this is like the 8bit segment, not just a single pixel)

/* Next let's create a register for holding all the init command bytes. We have a total of 16 init commands which take up a total of 25 bytes (some of the commands are 2 bytes). */
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
}; // Because the concat operator { and } places the most significant byte first, but also because we have inverted the indexing order, the first byte we write is actually placed at the beginning (0) of the array.

reg [7:0] commandIndex = 0; // register for the current command byte we are sending 

assign ioReset = reset; // connect the reset wire to the reset register
assign ioCs = cs; // connect the chip select wire to the chip select register
assign ioSclk = sclk; // connect the spi clock wire to the spi clock register
assign ioSdin = sdin; // connect the data input wire to the data input register
assign ioDc = dc; // connect the data/command select wire to the data/command select register

always_ff @(posedge clk) begin : spiTransferFSM
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
    STATE_SEND_BYTE: begin // to simplify implementation: we will just use two of our clock cycles for each bit being sent out.
      if(counter == 32'd0) begin // One, where the SPI clock will be pulled low and ...
        sclk <= 0; // Shift out/Change data - on falling edge
        sdin <= dataToSend[bitNumber];
        counter <= 32'd1;
      end else begin  // ... One, where the SPI clock will be pulled high.
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
      if(commandIndex == 0)
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
      dataToSend <= pixelData; // set the 'dataToSend' to the data we receive over the new 'pixelData' input
    end
  endcase
end

// For the pixel address we already have the 'pixelCounter' (byte Counter) variable so we can just connect them: 
assign pixelAddress = pixelCounter;

endmodule