// < The Top Module >
//
// With the 'hdmi_edid' module done, we need to create our 'top' module which will connect up all our other modules:
module top 
#(
  parameter STARTUP_WAIT = 32'd10000000
)
(
  //  As for ports:
  input  wire     clk,  // we ill receive the clk, 
  // the next 5 are all related to the OLED (SSD1361 - 128x64 pixels) screen's SPI connection, ...
  output reg      ioSclk,
  output reg      ioSdin,
  output reg      ioCs,
  output reg      ioDc,
  output reg      ioReset,
  // next we have the 2 I2C lines for the EDID information ...
  inout  logic    i2cSda,
  output reg      i2cScl,
  // ... and finally we have one of the on-board buttons so we can trigger another EDID reading.
  input  wire     btn1 
);

// For the screen we have our standard setup:
wire  [9:0]  pixelAddress;
wire  [7:0]  textPixelData;
wire  [5:0]  charAddress; 
reg   [7:0]  charOutput = " "; // = "A";

screen #(STARTUP_WAIT) scr(
  .clk(clk),  // This is the 
  .ioReset(ioReset), 
  .ioCs(ioCs),
  .ioSclk(ioSclk), 
  .ioSdin(ioSdin), 
  .ioDc(ioDc),
  .pixelAddress(pixelAddress), 
  .pixelData(textPixelData)
);

textEngine te(
  .clk(clk),
  .pixelAddress(pixelAddress),
  .pixelData(textPixelData),
  .charAddress(charAddress),
  .charOutput(charOutput)
);
// With this we can put any character we want to display on 'charOutput' and it will be drawn to the screen using our text engine and oled modules.

// For the I2C module we also connect it exactly like we connected the ADC in our previous article on I2C:
wire  [1:0]  i2cInstruction;
wire  [7:0]  i2cByteToSend; 
wire  [7:0]  i2cByteReceived; 
wire         i2cComplete; 
wire         i2cEnable; 

wire         sdaIn; 
wire         sdaOut; 
wire         isSending; 
assign       i2cSDA = (isSending & ~sdaOut) ? 1'b0 : 1'bz;
assign       sdaIn = i2cSda ? 1'b1 : 1'b0; 

i2c c(
  .clk(clk),  
  .sdaIn(sdaIn), 
  .sdaOut(sdaOut),
  .isSending(isSending),  
  .scl(i2cScl), 
  .instruction(i2cInstruction), 
  .enable(i2cEnable),  
  .byteToSend(i2cByteToSend), 
  .byteReceived(i2cByteReceived), 
  .complete(i2cComplete)
);

// Next we can instantiate our EDID module:
reg   enableEdid = 0; 
wire  edidDataReady; 
wire  [7:0]  edidDataOut;

hdmi_edid e(
 .clk(clk), 
 .enable(enableEdid),
 .dataReady(edidDataReady),  
 .instructionI2C(i2cInstruction), 
 .enableI2C(i2cEnable), 
 .byteToSendI2C(i2cByteToSend),
 .byteReceivedI2C(i2cByteReceived),
 .completeI2C(i2cComplete),
 .charIndex(charAddress[3:0]), 
 .rowIndex(charAddress[5:4]), 
 .edidDataOut(edidDataOut)
);

// Connecting it to our I2C and screen module's wires. To operate our EDID module we can create a mini state machine that just runs the module once at the start and waits 
// for a button press to restart the process
localparam EDID_STATE_READ_BYTE = 0;
localparam EDID_STATE_WAIT_FOR_START = 1;
localparam EDID_STATE_WAIT_FOR_VALUE = 2;
localparam EDID_STATE_DONE = 3; 

reg  [1:0]  edidState = EDID_STATE_READ_BYTE;

always_ff @(posedge clk) begin 
  if (~btn1) begin 
    edidState <= EDID_STATE_READ_BYTE;
    enableEdid <= 0;
  end else begin 
    case (edidState)
      EDID_STATE_READ_BYTE: begin 
        enableEdid <= 1;
        edidState <= EDID_STATE_WAIT_FOR_START;
      end
      EDID_STATE_WAIT_FOR_START: begin
        if (~edidDataReady) begin 
          edidState <= EDID_STATE_WAIT_FOR_VALUE;
        end
      end
      EDID_STATE_WAIT_FOR_VALUE: begin 
        if (edidDataReady) begin
          edidState <= EDID_STATE_DONE;
        end
      end
      EDID_STATE_DONE: begin 
        enableEdid <= 0;
      end
    endcase 
  end
end

// Finally for connecting up all the display data we can first setup some helper variables:
wire  [1:0]  rowNumber;
assign rowNumber = charAddress[5:4]; // The row number we get from the text engine ...
//  ... and the other two registers are the static strings we would like to display.
reg [7:0] NAME [0:5] = "Name:";
reg [7:0] RESOULUTION [0:11] = "Resolution:";

// We can then add another 'always' block to update the character to display based on the rowNumber and column index:
always_ff @(posedge clk) begin 
  if (rowNumber == 2'd0) begin 
    case (charAddress[3:0])
      0, 1, 2, 3, 4 : charOutput <= NAME[charAddress[2:0]];
      default: charOutput <= " ";
    endcase
  end
  if (rowNumber == 2'd1) begin 
    case (charAddress[3:0])
      13, 14, 15: charOutput <= " ";
      default: charOutput <= edidDataOut;
    endcase
  end
  else if (rowNumber == 2'd2) begin 
    case (charAddress[3:0])
      0, 1, 2, 3, 4, 
      5, 6, 7, 8, 9 : charOutput <= RESOULUTION[charAddress[3:0]];
      default: charOutput <= " ";
    endcase
  end
  else if (rowNumber == 2'd3) begin 
    case (charAddress[3:0])
      4:  charOutput <= "x";
      9:  charOutput <= "p";
      10: charOutput <= "x";
      11: charOutput <= "@";
      14: charOutput <= "H";
      15: charOutput <= "z";
      default: charOutput <= edidDataOut;
    endcase
  end
end
// Taking a look at the screen layout again :
//  
// ... (ref. screen-layout-edid-info.png)
//
// This code complements the screen code we did in the Edid module by filling in the static characters and deferring to the edid character for the indices that are dynamic.
endmodule


// < Physiscal Setup >
//
// With the code done, the next thing we need to do is hook-up our constraints file. Create a new .cst file with the following ports:
//
// ... (ref. pinning-constraints.jpg)
//
// We have the clk signal and screen spi connection like usual, we also have 1 of the buttons hooked up and for the EDID connection we need two i2c ports 1 for the clock and 1 for data.
//
// I chose pins 31 and 32 for no special reason other then them being consecutive and close to where I needed the signal to be on my breadboard but any of the 3.3 volt IOs would have worked.
//
// The last step is the electrical connection, and here there are a few things we need to deal with. The first issue, is that the DDC wires from the on-board HDMI connector are not connected to the 
// FPGA, so we will need an alternate way of connecting these signals, and the second problem is that these signals are 5 volts and we are working with 3.3 volts.
//
// For the first issue, there really aren't that many options, if you have a spare HDMI cable that you don't mind cutting up you can manually extract these two wires along with the 5V and ground lines 
// for this interface. Another good option is by using an HDMI breakout board like the following:
//
// ... (ref. hdmi-breakout-1.png)
//
// There are fancier ones out there with screw terminals or whatever, but I tested this generic passthrough one which only costs a dollar or two and I had no issues.
// 
// Using something like this you can easily extract pins 17 and 18 are the 5 volt and ground signal we need and pins 15 and 16 are the I2C signal (15 is the clock and 16 the data).
//
// Next for the conversion from 3.3 volts to 5 volts we need some kind of level shifter. I2C uses pull-up resistors and each side can only pull the signal low, so there are simple 1 transistor solutions
// that do the conversion and you can get a board like the following:
//
// ... (ref. level-shifter.png)
//
// Which can convert up to 4 signals, the way it works is you power the HV (high voltage) pin with 5 volts and the LV pin with 3.3 volts, connect the grounds and then you can use each of the 4 channels
// to translate the voltage bidirectionally.
//
// I ended up using a Sparkfun level shifter I had on-hand with a PCA9306 IC on-board to do the conversion:
//
// ... (ref. level-shifter-2.png)
//
// Other then that I also added some diodes to the 5v and 3.3v lines as-well as to the ground signal to protect the tang nano and make sure I wasn't getting current going from the 5v line to the 3.3v 
// line (without the diodes I was getting some crossover causing the tang nano not to turn on, adding the diodes solved the issue). So with all the pieces in place you should have something like the
// following:
//
// ... (edid-schematic-diodes.png)
//
// With that done you should be able to run the project and read the EDID info.
//
// Don't get frightened by the mess of wires, this image was taken during a debug session where I was trying to find where the leak from 5 volts to the 3.3 volts was happening. hence the 5 diodes.
// 
// < Conclusion > 
// 
// In this article we explored the EDID protocol and how to use the HDMIs I2C channel to retrieve this information. Thanks again to Jeroen and Martijn for all the help turning this idea into a
// functional "product" that could be used to solve a real world problem.
//