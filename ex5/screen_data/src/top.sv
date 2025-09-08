// In-order to build the project we need another module which will connect our two modules together, let's create a new file called top.v 
// which will be our top module:

// In this article we will go through different methods of converting data for display and we will be combining all the modules we created up until now in-order to wrap up our OLED mini project. 

// The Goal
// We will be building a project that splits the screen into 4 rows like in the previous article, but here each row will have a different data representation / conversion and will show how we can 
// update multiple areas of the screen in parallel using our design.
// The first row of the screen will display ASCII text, much like we did last time, except now we will connect it to our UART module we built here to make the text dynamic. So as you type on the 
// computer the text will be displayed on the first row. Since both the data coming in over UART and the data going out to our text engine are both ASCII format, no conversion is required here.
// 
// Next, we will have an 8-bit counter which will count once a second which we are using to give us a binary number. We are using a counter to keep it simple but this could be a sensor value or 
// calculation result and besides for changing the counter module all the rest of the design would stay the same.
// 
// The next two lines of the screen will be used to display the number both in binary, hex and in decimal format. So in the case of the binary row we have to convert the 8-bit number into 8 ascii 
// bytes each of which can be a '1' or '0' (49/48 ascii code). For hex and decimal we need to convert the number to it's representation in base 16 / base 10 respectively and convert the result
// into ASCII characters.
//
// The final row will not use our text engine and will show how we can combine both graphics and text on screen. This last row will be a simple progress bar where when our counter is 0 the 
// progress bar would be empty and for 255 it would be full.

module top#(
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT = 32'd10000000
)
(
  input wire EXT_CLK,  // This is the external clock source on the board - expected 27 [MHz] oscillator. 
  input wire BTN_S1, // This pin is tied to a button 'S1' on the board, and will be used as a 'reset' source (active-low) 
  input wire BTN_S2, // This pin is tied to a button 'S2' on the board, and will be used as a general user input source (active-low) 
  output reg [5:0] LED_O=6'b1, // 6 Orange LEDs on the board, active-low , default to all high (leds are OFF)
  // LCD 0.96" SPI interface - SSD1306 controller
  output wire LCD_SPI_RST, // reset: active-low  
  output wire LCD_SPI_CS, // chip-select: active-low Note: multiple bytes can be sent without needing to change the chip select each time.
  output wire LCD_SPI_SCLK, // spi clock signal: idle-low 
  output wire LCD_SPI_DIN, // data input. Note: data is latched on the rising edge of the clock and is updated on the falling edge. MSb is sent first.
  output wire LCD_SPI_DC,  // data/command select: active-low - data, active-high - command
  input  wire UART_RX
);

wire [9:0] pixelAddress;
wire [7:0] textPixelData, chosenPixelData; 
wire [5:0] charAddress;
reg  [7:0] charOutput;

wire uartByteReady; // indicator flag
wire [7:0] uartDataIn; 
wire [1:0] rowNumber; // We have reorganized the LCD to be 4 rows x 16 columns chars. 

// We create instances of our screen driver ... 
screen #(STARTUP_WAIT) scr(
  .clk(EXT_CLK),
  .ioReset(LCD_SPI_RST), 
  .ioCs(LCD_SPI_CS), 
  .ioSclk(LCD_SPI_SCLK), 
  .ioSdin(LCD_SPI_DIN), 
  .ioDc(LCD_SPI_DC),  
  .pixelAddress(pixelAddress), // we're reading the pixel LCD segment address and based on that ...
  .pixelData(chosenPixelData)  // ... we're writing the desired byte-pixel LCD segment to the screen. 
);


// ... instance of text engine ...
textEngine te(
  .clk(EXT_CLK),
  .pixelAddress(pixelAddress),
  .pixelData(textPixelData),
  .charAddress(charAddress),
  .charOutput(charOutput)
);

assign rowNumber = charAddress[5:4]; // Extract the [3:0] bits - are the character (column) indexing, while [5:4] signify the row

// ... instance of uart module.
uart u(
  .clk(EXT_CLK),
  .uartRx(UART_RX),
  .byteReady(uartByteReady),
  .dataIn(uartDataIn) 
);

// ... Instantiate and hookup our UART text row:
wire [7:0] charOut1;

uartTextRow row1(
  .clk(EXT_CLK),
  .byteReady(uartByteReady),
  .data(uartDataIn), 
  .outputCharIndex(charAddress[3:0]),
  .outByte(charOut1)
);

// Add the following for the 'binaryRow' module:
wire [7:0] counterValue;
wire [7:0] charOut2;

counterM cntM(
  .clk(EXT_CLK),.counterValue(counterValue));

binaryRow row2(
  .clk(EXT_CLK),
  .value(counterValue),
  .outputCharIndex(charAddress[3:0]),
  .outByte(charOut2)
);

// Faciliate the connection to the 'top' of our 'hexDecRow'
wire [7:0] charOut3;
hexDecRow row3(
  .clk(EXT_CLK),
  .value(counterValue),
  .outputCharIndex(charAddress[3:0]),
  .outByte(charOut3)
);

// To facilitate / hook the progress bar module ('progressRow') to our design - add the following to our top module
wire [7:0] progressPixelData;
progressRow row4(
  .clk(EXT_CLK),
  .value(counterValue),
  .pixelAddress(pixelAddress),
  .outByte(progressPixelData)
);

// The last always block will choose a character for now according to the rowNumber. So the whole first row should be "A" and the second "B" and so on, 
// this is instead of the textRow component from the previous article.
always_ff @(posedge EXT_CLK) begin
  case(rowNumber) 
    0: charOutput <= charOut1; // ASCII val: include the output 'charOut1' from our new module - 'uartRow' for the 1st row.
    1: charOutput <= charOut2; // ASCII val: update our always block to take charOut2 for the 2nd row.
    2: charOutput <= charOut3; // ASCII val: update the Hexadecimal and Decimal Texts
    //3: charOutput <= "D";   // NOTE: This case will not be used! As for row 3 we're not going to print ASCII characters, but graphics
  endcase 
end

// It's worth noting that here we are not using the character address anymore but the actual pixelAddress from the screen. That is because we want to receive / decide what to draw for all 128 columns 
// independently as we are drawing graphics. As apposed to the character address which only goes through 16 indices for characters. The output here is also the actual pixel data and not the ASCII value.
// So to connect this row we don't change the always block like for the previous row, since that block decides what goes into the text engine. Here we want to change what goes to the screen. 
// So we can replace the row where we assigned 'chosenPixelData' with the following:
assign chosenPixelData = (rowNumber == 3)? progressPixelData : textPixelData; // So if we are on the last row we will send the progress bar data to the screen, otherwise we will connect the output of the text engine.
endmodule

// To test 'binaryRow' out we need to have a value to display, so let's add to top.v a simple counter module based on our previous counter from the first article in this series.
module counterM(
  input wire clk, // expected 27 [MHz] clock as input 
  output reg[7:0] counterValue = 0   // output an bit counter which updates once in a tenth of a second - 0.1 [Hz]
);

localparam WAIT_TIME = 2700000;

reg [32:0] clockCounter = 0;

always_ff @(posedge clk) begin 
  if(clockCounter == WAIT_TIME) begin 
    clockCounter <= 0;
    counterValue <= counterValue + 1;
  end else 
    clockCounter <= clockCounter + 1;
end 
endmodule