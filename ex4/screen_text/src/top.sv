// In-order to build the project we need another module which will connect our two modules together, let's create a new file called top.v 
// which will be our top module:
module top#(
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037 // external clock source, period in [ns], 
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

wire [9:0] pixelAddress;
wire [7:0] pixelData; 

screen scr(
  .clk(EXT_CLK),
  .ioReset(LCD_SPI_RST), 
  .ioCs(LCD_SPI_CS), 
  .ioSclk(LCD_SPI_SCLK), 
  .ioSdin(LCD_SPI_DIN), 
  .ioDc(LCD_SPI_DC),  
  .pixelAddress(pixelAddress),
  .pixelData(pixelData)
);

textEngine te(
  .clk(EXT_CLK),
  .pixelAddress(pixelAddress),
  .pixelData(pixelData)
);

endmodule