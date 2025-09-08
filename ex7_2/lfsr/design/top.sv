

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

  input  wire UART_RX,  // UART|RX pin - 8N1 config
  output wire UART_TX,  // UART|TX pin - 8N1 config
  
  output wire FLASH_SPI_CS,  // chip select for flash memory
  output wire FLASH_SPI_MOSI, // master out slave in for flash memory
  input  wire FLASH_SPI_MISO, // master in slave out for flash memory
  output wire FLASH_SPI_CLK  //  clock signal for flash memory
);
localparam STARTUP_WAIT_CYCL = ((EXT_CLK_FREQ/1000)*STARTUP_WAIT_MS);

wire  [9:0] pixelAddress; // value 0 - 1023, the current display cursor addr
reg   [7:0] pixelData; // the 8-bit pixel data , which covers a 8 pixel column

// Some Boilerplate
// So in our project we should have screen.v and lfsr.v (and the test file lfsr_tb.v). The next step is to create our Makefile:
//
// Implementing the Grapher
// To get started let's create top.v adding all the inputs and outputs from the constraints file:
screen #(STARTUP_WAIT_CYCL) scr ( // Hook up our screen module.
 .clk(EXT_CLK),
 .ioReset(LCD_RST),
 .ioCs(LCD_SPI_CS),
 .ioSclk(LCD_SPI_SCLK),
 .ioSdin(LCD_SPI_DIN),
 .ioDc(LCD_DC),
 .pixelAddress(pixelAddress),
 .pixelData(pixelData)
);

// Next let's create a 32-bit LFSR which we will use to generate our random numbers:
wire randomBit; // // We create a wire to output the random bit from the LFSR ...
lfsr #( // ... and then create a new LFSR instance setting the parameters to be a 32-bit LFSR with a valid taps for such a size.
  .SEED(32'd1),
  .TAPS(32'h80000412),
  .NUM_BITS(32)
) l1 (
  EXT_CLK,
  randomBit
);

reg [3:0] tempBuffer = 0; // We then create a 4-bit buffer to hold our 4-bit random number which we will use to update our running total.
always_ff @(posedge EXT_CLK) begin  // The always block will shift in the random bit on every clock pulse, pushing all the other bits up.
  tempBuffer <= {tempBuffer[2:0], randomBit};
end

// Next up we need some registers for storing our graph data. Like mentioned above, we will want to store 128 graph values (data points) one for each column. If we say that each number
// is an 8-bit number, then we will need 8 * 128 bits.
localparam NUM_PIXELDATA_STORAGE = 128; // So we have a local parameter holding the number of pixel bytes, ...
reg [7:0] graphStorage [0:NUM_PIXELDATA_STORAGE-1] = '{default:0}; // ... then a new register to hold all 128 pixel bytes.

reg [7:0] graphValue = 127; // Next we have a register to hold the current running total, we initialize it to 127, so it will start out in the middle of the graph. (fill the bar-indication at half)
reg [6:0] graphColumnIndex = 0; // register graphColumnIndex stores which byte in graphStorage we currently need to write to ...
reg [19:0] delayCounter = 0; // ... and finally delayCounter will count clock cycles to delay taking a new random number.

// If we would update the graph at full speed it would be too fast and would look just like random noise. To make it look like a real-time graph we need to slow it down, so we will wait 
// 900,000 clock cycles between saving a new datapoint to our graph giving us about 30 FPS (27MHZ / 900,000 = 30).
// Now let's take a look at the actual code that will do this:
always_ff @(posedge EXT_CLK) begin 
  if(delayCounter == 20'd900000) begin //  If our delayCounter reached 900,000 then ...
    if(tempBuffer != 4'd15) //  we don't update the running total when the tempBuffer was 15 to essentially treat 8 (15-7) as another zero.
      graphValue <= graphValue + tempBuffer - 8'd7; // we update the current graphValue (for next time) and ...
    delayCounter <= 0;                              
    graphStorage[graphColumnIndex] <= graphValue; // ... we store the last value into graphStorage.
    graphColumnIndex <= graphColumnIndex + 1;
  end else  
    delayCounter <= delayCounter + 1;
end
// We don't want our graph to only go up, so we subtract 7 from the number to change our 4-bit number from being 0-15 to be -7 to 8.  The problem with this is that we have more positive numbers 
// then negative so to get around this, we don't update the running total when the tempBuffer was 15 to essentially treat 8 (15-7) as another zero. This makes the positive and negative numbers
// balanced making our graph less likely to go out of bounds.
// With that we now have storage which updates 30 times a second and has 128 total columns of random bytes. The last step is to just draw them to the screen.

// Drawing the Columns
// The way our screen works is it will set a specific pixel byte address inside pixelAddress for a byte representing 8 pixels on screen. We have about 20 clock cycles to calculate what needs to be 
// displayed and put the value inside of pixelData. Let's start out by splitting up the requested pixelAddress into an X and Y coordinate on screen:
wire [6:0] xCoord; // We have 128 columns which means we need 7-bits for the X direction ...
wire [2:0] yCoord; // ... and we have 8 rows (of 8 (vertical) pixel bits each) requiring 3-bits.
// Each of the addresses represents 8-vertical pixels giving us a total of 64 pixels in height. 

assign xCoord = pixelAddress[6:0] + graphColumnIndex; // it is simply the first 7 bits from  pixelAddress. We add to this graphColumnIndex to offset the screen position to create a scrolling effect
// every time we store a new value in the graph storage we increment the graphColumnIndex value so by adding it here we shift the X-axis by the same amount making each column display the value that 
// was in the next column essentially scrolling the graph backwards by one.
assign yCoord = 3'd7-pixelAddress[9:7]; // For the Y coordinate, theoretically we only need the last 3-bits of pixel address. The screen coordinate system places (0,0) at the top left and (127,7) at 
// the bottom right. We want to flip the Y coordinate so that 0 is at the bottom and 7 is at the top, to do this we simply start with 7 and subtract the screen's Y coordinate flipping the axis.

// Next we need to get the current value to display from graphStorage based on the current address:
wire [7:0] currentGraphValue;
wire [5:0] maxYHeight;

assign currentGraphValue = graphStorage[xCoord]; // The first 8-bit wire will hold the current value to display from the graph storage. Each time we will be filling out a byte for a single column
                                                 // of pixels and each byte in graphStorage is for a single column making it so we only need to retrieve 1 byte to calculate how to render the graph. 
assign maxYHeight = currentGraphValue[7:2]; // MaxYHeight is just to convert it to the screen's dimensions, currentGraphValue can be a number from 0-255 yet our screen only has 64 pixels in height so 
                                            // we divide by 4 via removing the last two bytes (like shifting right by 2).

// The final step is to calculate which pixels in the current byte we want to draw. maxYHeight has already been mapped to pixels by dividing it by 4, so let's say currently the value of maxYHeight 
// is 25 that would mean we want the bottom 25 pixels in the column to be lit up and the rest not.
always_ff @(posedge EXT_CLK) begin 
  pixelData[0] <= ({yCoord, 3'd7} < maxYHeight);
  pixelData[1] <= ({yCoord, 3'd6} < maxYHeight);
  pixelData[2] <= ({yCoord, 3'd5} < maxYHeight);
  pixelData[3] <= ({yCoord, 3'd4} < maxYHeight);
  pixelData[4] <= ({yCoord, 3'd3} < maxYHeight);
  pixelData[5] <= ({yCoord, 3'd2} < maxYHeight);
  pixelData[6] <= ({yCoord, 3'd1} < maxYHeight);
  pixelData[7] <= ({yCoord, 3'd0} < maxYHeight);
end
// On each clock cycle we set each of the 8 pixel bits to be 1 if the pixel Y index is less than the max height we calculated from graph storage. The value in yCoord is the byte index so to get a 
// bit index we multiply by 8 and then each pixel index get's a different suffix from 0-7.
// So for example if yCoord equals 1, that means that we are now dealing with pixels row indexed 8-15 by shifting 3 and adding the number 0-7 we get all these indices. For each pixel index we 
// simply need to compare it to maxYHeight and if it is lower than or equals then it will return 1 lighting the specific pixel up.
// The reason the numbers are reversed, like in pixelData[0] we put yCoord + 7 and not yCoord + 0 is because we flipped the Y axis so it is reversed.

endmodule

// Conclusion
// In this part we took a look at generating pseudo-random numbers using LFSRs and built a scrolling graph to show us the random number affecting a running total over time.
// Going through LFSRs I hope it was clear that it might not be the best match for security systems as there is a correlation between numbers, but for most user-based applications where you just 
// need a bit of "randomness" it is very cheap to implement both in design and in the number of resources required to provide pretty good results.