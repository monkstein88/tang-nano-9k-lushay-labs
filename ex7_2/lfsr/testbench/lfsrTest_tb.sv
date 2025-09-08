

module lfsrTest_tb();
  // rule of thumb
  reg  clk = 0; //  use registers if it is an input into the module to drive the value 
  wire randomBit; // use wires if it is an output from the module itself, that will drive the value.

lsfrTest testLFSR(
  .clk(clk),
  .randomBit(randomBit)
);

// Let's now take a look if we don't reuse bits and only take 3-bit numbers.
reg [2:0] tempBuffer = 0; // create a buffer to hold the bits as they are shifted off the LFSR
reg [1:0] counter = 0; // create another register to count every time we got 3 new bits 
reg [2:0] value; // and a final register to store the value once ready.

always_ff @(posedge clk) begin  // Inside the clock loop ...
  if(counter == 3) begin  // ... we check for when the counter reaches 3 ... 
    value <= tempBuffer; // ...  in which case we transfer the temp value into the value register.
  end
  counter <= counter + 1; // Other then that we always increment the counter ... 
  tempBuffer <= {tempBuffer[1:0], randomBit}; // ...  and shift the new randomBit into our temp buffer shifting everything up.
end
// Looking at the output of this - The first two numbers are not defined ('z') as we didn't initialize our registers with a value but it's ok since not all the bits are random there.
// Looking at the sequence now we get: 2,3,3,1,7,3,4,0,5,7,6,3,6,6,1,0,2,6,4,7,4,5,2,1,5,5,0,7,1,2,4
//
// Our sequence length is still 31 but now since we are reading smaller bit-sized numbers we have multiple duplicates of each number 4 to be exact since we left off two bits and 2^2 = 4.
// Except for 0 which there is only 3 since one of the options is when the LFSR equals all zeros which is not a valid case.
//
// Another benefit here is you can see there are some streaks and also if you get a number for example a 2 you don't know the next number as it could be a 3,6,1 or 4 because of the multiple occurrences.
//
// Adding the fact that you let it run at 27MHZ that means it goes through the whole cycle about 900,000 times a second or about 1 micro-second. If you only take a number based on for example user-input
// like a button press, a person can't reliably time their button presses to 1/31-th of a microsecond to get a specific number in the sequence making it pretty much random for most use-cases.
//
// Before we start playing with LFSRs let's see how we can generalize our module so we don't need to create a new one for each different LFSR we add.

// The way to simulate the clock signal.
always begin 
  #1 clk = ~clk; // The #number (#1) is a special simulation syntax from iverilog that allows us to delay something by a certain number of time frames. 
                 // By saying each time interval the clock alternates, we are saying the clock cycle is 2 time units (1 high cycle and 1 low cycle is 1 clock cycle).
                 // So this loop will wait 1 time unit and toggle the clock register.
end 

initial begin 
  $display("Starting LFSR Test"); // print out a string optionally injecting variables into it - performed once
  //$monitor("LFSR: 'sr': %d", lfsrTest_tb.testLFSR.sr); // print out a string optionally injecting variables into it - will print it out, and then reprint it out any time the value changes. 
  $monitor("LFSR 'value': %d", lfsrTest_tb.value); 
  #1000 $finish; // stops the simulation, so after 1000 more time frames we stop the simulation.
end

// For visually debugging the logic we can add another block to dump a VCD file.
initial begin 
  $dumpfile("lfsrTest_tb.vcd"); // $dumpfile chooses the name of the file - VCD file 
  $dumpvars(0,lfsrTest_tb); // chooses what to save and how many levels of nested objects to save. By sending 0 as the number of layers it means we want all nested layers
                            // (which will include our LFSR test module), and by sending the top module test it means store everything and all child wires / registers.
end

endmodule

// The Implementation
// Implementation wise it couldn't be any easier we just need a register with the number of bits we want in the LFSR and we need to connect some of the bits to the input of the first bit based on 
// the taps we chose.
// 
// Taking our 5 bit LFSR from before we can create a simple verilog file like the following:
module lfsrTest(
  input   wire  clk, 
  output   reg  randomBit = 0
);

  reg  [4:0] sr = 5'b00001;
  
  always_ff @(posedge clk) begin 
    sr <= {sr[3:0], sr[4] ^ sr[1]};
    randomBit <= sr[4];
  end
// We seed the shift register with an initial value of 1 and on each clock pulse we shift the bits up and calculate the new input bit for b0 by XOR-ing bit 4 and bit 1 together. We then set the output 
// register which holds the random bit to the value of b4 in our shift register (the bit we shifted off).
// 
// Running this would produce the following sequence:
// 1,2,5,10,21,11,23,14,29,27,22,12,24,17,3,7,15,31,30,28,25,19,6,13,26,20,9,18,4,8,16
//
// With five bits we have 2^5 options -1 removing the zero case we get a period of 31 numbers. And as you can see the order seems pretty random. Already looks pretty good but again there is some
// correlations where you can see the number just doubling because of the shift for example at the beginning or end of the sequence.
endmodule

