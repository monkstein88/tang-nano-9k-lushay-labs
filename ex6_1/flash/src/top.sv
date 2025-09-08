// Tang Nano 9K: Reading the External Flash
// In this article we will be taking a look at the onboard external flash that comes on the Tang Nano9K. The onboard flash provides a whopping 4MB of storage which is both useful for applications where you need a 
// lot of data, or even in applications where you simply want to store persistent data which will not be erased on power off.
// Covering both reading and writing to flash would make this article a bit long, so in this part we will focus on exploring the flash chip and reading data from it and in the next section we will go over writing 
// to the flash chip persisting data in your application.
// The Plan
// To showcase reading data off the flash chip we will be building a hex viewer where we can display on screen a section of memory in hex format and have the ability to traverse through the different memory 
// addresses using the on-board buttons.
// We won't go through the whole datasheet but to go over some of the highlights:
// 1. 24-bit address from 000000 to 3FFFFF in hex to access all 4 megabyte.
// 2. Each address points at a single byte.
// 3. The bytes are reset to FF not 00.
// There are also some more advanced features like locking certain areas of memory or clearing the entire memory in a single operation but we won't be covering those features.
//
// We can also see the IC supports multiple communication methods like SPI, Dual SPI, Quad SPI, etc. but from the tang nano 9K schematic we can see we only have a single SPI connection so only the standard SPI is relevant.
//
// We can see we have to set the chip select to low since it's active low, we then send the command, changing the bit on the MOSI pin on the falling edge and the command will be read on the rising edge.
// After sending the command we send 24 bits representing the address and then we need to pulse the clock another 8 times for each byte we want to read. The flash chip will continue to output bytes in order for as 
// many as we want, we can even read the full memory from a single read command. To stop reading we need to set the CS pin back high to stop the transmission.
//
// In our example since our screen can display a total of 64 characters (4 rows of 16) and each byte takes up two characters in hex (two 4-bit nibbles), we will be reading 32 bytes so we can fill the entire screen each 
// time we read data.
//
// We can also see from the datasheet that their is a bit of time required after power up to make sure the IC has initialized. There is a status flag we could check to make sure the chip is up, but we will just wait a fixed 
// period where we can be sure it will be ready.
// Other then that we can see from Chapter 5.3 that the max frequency for reading is 33Mhz which is above our 27Mhz oscillator on the tang nano and their is no minimum speed so we don't have any special requirements to
// take into consideration in terms of speeds.
// We now have everything we need in terms of info to start developing our hex viewer.

module top
#(
  /* Tang Nano 9K Board - featuring GOWIN FPGA: GW1NR-LV9 QFN88P (rev.C) */
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT_MS = 10 // make startup delay of 10 [ms]
)
(
  input wire EXT_CLK,  // This is the external clock source on the board - expected 27 [MHz] oscillator. 
  input wire BTN_S1, // This pin is tied to a button 'S1' on the board, and will be used as a 'reset' source (active-low) 
  input wire BTN_S2, // This pin is tied to a button 'S2' on the board, and will be used as a general user input source (active-low) 
  output reg [5:0] LED_O=6'b1, // 6 Orange LEDs on the board, active-low , default to all high (leds are OFF)
  // LCD 0.96" SPI interface - SSD1306 controller
  output wire LCD_RST, // reset: active-low   
  output wire LCD_SPI_CS, // chip-select: active-low Note: multiple bytes can be sent without needing to change the chip select each time.
  output wire LCD_SPI_SCLK, // spi clock signal: idle-low 
  output wire LCD_SPI_DIN, // data input. Note: data is latched on the rising edge of the clock and is updated on the falling edge. MSb is sent first.
  output wire LCD_DC,  // data/command select: active-low - data, active-high - command

  input  wire UART_RX, // UART|RX pin - 8N1 config
  output wire UART_TX,  // UART|TX pin - 8N1 config
  
  output wire FLASH_SPI_CS,  // chip select for flash memory
  output wire FLASH_SPI_MOSI, // master out slave in for flash memory
  input  wire FLASH_SPI_MISO, // master in slave out for flash memory
  output wire FLASH_SPI_CLK  //  clock signal for flash memory
);
localparam STARTUP_WAIT_CYCL = ((EXT_CLK_FREQ/1000)*STARTUP_WAIT_MS);
wire  [9:0] pixelAddress;
wire  [7:0] textPixelData;
wire  [5:0] charAddress; 
wire  [7:0] charOutput; 

// Another thing that is important to note, is that the buttons are on the 1.8V bank and the flash chip is in the 3.3V bank. Connecting these two banks 
// (by using them in the same expression or connecting each to the same registers) will cause a compilation error while generating the bitstream as to 
// not accidentally mix the different voltage levels. To get around this we can do something like the following:
reg btn1Reg = 1, btn2Reg = 1;
always @(negedge EXT_CLK) begin 
  btn1Reg <= BTN_S1 ? 1 : 0;
  btn2Reg <= BTN_S2 ? 1 : 0;
end
// Here we create a register for each of the buttons and we don't assign the button directly to the register (making the register also connect to the 1.8V bank) 
// but instead we use the button value to multiplex a separate value into the register. By multiplexing a separate 1 / 0 into the register it lets nextPnR separate
// the two banks and we won't need to worry about mixing signals.

// the screen iterates over all pixels on screen in 1024 bytes. Each time it requests a single byte using the pixelAddress register ...
screen #(STARTUP_WAIT_CYCL) scr(
  .clk(EXT_CLK),
  .ioReset(LCD_RST),
  .ioCs(LCD_SPI_CS),
  .ioSclk(LCD_SPI_SCLK),
  .ioSdin(LCD_SPI_DIN),
  .ioDc(LCD_DC),
  .pixelAddress(pixelAddress),
  .pixelData(textPixelData)
);
// ... The text engine takes this pixel address and converts it into a character index by splitting the screens pixels into 4 rows of 16 characters...
textEngine te(
  .clk(EXT_CLK),
  .pixelAddress(pixelAddress),
  .pixelData(textPixelData),
  .charAddress(charAddress),
  .charOutput(charOutput)
);

// ... The 'flashNavigator' takes this character index and decides which of the 32 bytes we read from memory we want to display and which of its two hex characters 
// for the current byte we need to display. The ASCII result is sent back to the text engine using the charOutput wire which the text engine then converts to 
// individual pixels which the screen needs in-order to draw the current pixels. This is done with textPixelData.
flashNavigator externalFlash(
  .clk(EXT_CLK),
  .flashClk(FLASH_SPI_CLK),
  .flashMiso(FLASH_SPI_MISO),
  .flashMosi(FLASH_SPI_MOSI),
  .flashCs(FLASH_SPI_CS),
  .charAddress(charAddress),
  .charOutput(charOutput),
  .btn1(btn1Reg),
  .btn2(btn2Reg)
);

endmodule
