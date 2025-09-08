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