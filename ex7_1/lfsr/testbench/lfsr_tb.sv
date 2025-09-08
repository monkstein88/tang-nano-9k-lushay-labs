// With that we now have a fully working LFSR of any size and any tap configuration. To test it let's create a test bench so we can simulate a few different LFSRs 
// so in a file called lfsr_tb.v:
module test();
  reg clk = 0;
  wire l1Bit, l2Bit, l3Bit; 

  // we are simply creating 3 LFSRs. They are all 5 bits with an initial seed of 1, but each has a different tap configuration.
  lfsr #(
    .SEED(5'd1),
    .TAPS(5'h12),
    .NUM_BITS(5)
  ) l1 (
    clk,
    l1Bit
  );

  lfsr #(
    .SEED(5'd1),
    .TAPS(5'h1B),
    .NUM_BITS(5)
  ) l2 (
    clk,
    l2Bit
  );

  lfsr #(
    .SEED(5'd1),
    .TAPS(5'h1B),
    .NUM_BITS(5)
  ) l3 (
    clk,
    l3Bit
  );

  // The way to simulate the clock signal.
  always begin 
    #1 clk = ~clk; // The #number (#1) is a special simulation syntax from iverilog that allows us to delay something by a certain number of time frames. 
                  // By saying each time interval the clock alternates, we are saying the clock cycle is 2 time units (1 high cycle and 1 low cycle is 1 clock cycle).
                  // So this loop will wait 1 time unit and toggle the clock register.
  end 
  
  // Start & Stop the simulation
  initial begin 
    $display("Starting LFSR Test"); // print out a string optionally injecting variables into it - performed once
    #1000 $finish; // stops the simulation, so after 1000 more time frames we stop the simulation.
  end

  // For visually debugging the logic we can add another block to dump a VCD file.
  initial begin 
    $dumpfile("lfsr.vcd"); // $dumpfile chooses the name of the file - VCD file 
    $dumpvars(0,test ); // chooses what to save and how many levels of nested objects to save. By sending 0 as the number of layers it means we want all nested layers
                        // (which will include our LFSR test module), and by sending the top module test it means store everything and all child wires / registers.
  end
endmodule