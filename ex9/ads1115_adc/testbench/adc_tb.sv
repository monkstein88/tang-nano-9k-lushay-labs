// < Testing the ADC >
//
// To test we need to create a new testbench file, so let's create a file called 'adc_tb.v'. We can start off with some boilerplate:

// Set simulation - time unit of 10 [ns], and time precision of 1 [ns]
`timescale 10ns/1ns
module test();
  // Clock signal:
  reg clk = 0;
  // Clock generation (infinite loop) process - toggle each 'time unit'
  always begin 
    #1 clk = ~clk; // The #number (#1) is a special simulation syntax from iverilog that allows us to delay something by a certain number of time frames. 
                   // By saying each time interval the clock alternates, we are saying the clock cycle is 2 time units (1 high cycle and 1 low cycle is 1 clock cycle.
                   // So this loop will wait 1 time unit and toggle the clock register.
  end 

  // Simulation Run - for setting Start & Stop of test bench duration
  initial begin 
    $display("Starting ADC Module Test") ; // print out a string optionally injecting variables into it - performed once
    #100_000 $finish; //  set the length of our test to 100000 'time units' (where each clock cycle is 2 time units). 
  end
 
  // Simulation Waveform - for visually debugging the logic we can add another block to dump a VCD file.
  initial begin 
    $dumpfile("adc.vcd");  // $dumpfile chooses the name of the file - VCD file 
    $dumpvars(0,test);    // chooses what to save and how many levels of nested objects to save. By sending 0 as the number of layers it means we want all nested layers
                           // (which will include our 'adc' and 'i2c' module), and by sending the top module test it means store everything and all child wires / registers.
  end 

  wire [1:0] i2cInstruction;
  wire [7:0] i2cByteToSend;
  wire [7:0] i2cByteReceived;
  wire i2cComplete;
  wire i2cEnable;

  wire i2cSda;

  wire i2cScl;
  wire sdaIn;
  wire sdaOut;
  wire isSending;
  assign i2cSda = (isSending & ~sdaOut) ? 1'b0 : 1'b1; //  create a wire called 'i2cSda' so we will simulate how the tri-state wire will be hooked up.
  assign sdaIn = i2cSda ? 1'b1 : 1'b0;
  
  // We create all the wires the 'i2c' module needs and we also create a wire called 'i2cSda' so we will simulate how the tri-state wire will be hooked up.
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

  // Next we just need a few more registers for adding our ADC module:
  reg [1:0] adcChannel = 0;
  wire [15:0] adcOutputData;
  wire adcDataReady;
  reg adcEnable = 1;

  adc #(7'b1001001) a( // We will hard-code the channel to channel 0 and set enable high so it will start a conversion. Other then that two wires that are required by our adc module.
    .clk(clk), 
    .channel(adcChannel),  
    .outputData(adcOutputData),
    .dataReady(adcDataReady), 
    .enable(adcEnable), 
    .instructionI2C(i2cInstruction),
    .enableI2C(i2cEnable),
    .byteToSendI2C(i2cByteToSend),
    .byteReceivedI2C(i2cByteReceived),
    .completeI2C(i2cComplete)
  );

endmodule

// Running this test will create a VCD file with the entire conversion process.