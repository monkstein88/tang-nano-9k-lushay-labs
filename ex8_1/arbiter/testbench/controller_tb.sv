// < Testing Our Controller >
// To test our module and create a VCD file where we can visualize our module in action we can create a file called controller_tb.v with the following:
module test();
  reg clk = 0;

  // Clock generator - simple toggle each #1 clk cycle
  always begin  
    #1 clk = ~clk; // The #number (#1) is a special simulation syntax from iverilog that allows us to delay something by a certain number of time frames. 
                   // By saying each time interval the clock alternates, we are saying the clock cycle is 2 time units (1 high cycle and 1 low cycle is 1 clock cycle).
                   // So this loop will wait 1 time unit and toggle the clock register.
  end 

  // Configuration section - for setting Start & Stop of test bench duration
  initial begin 
    $display("Starting CONTROLLER Test") ; // print out a string optionally injecting variables into it - performed once
    #1000 $finish; // stops the simulation, so after 1000 more time frames we stop the simulation.
  end
 
  // Configuration section - for visually debugging the logic we can add another block to dump a VCD file.
  initial begin 
    $dumpfile("controller.vcd");  // $dumpfile chooses the name of the file - VCD file 
    $dumpvars(0,test);  // chooses what to save and how many levels of nested objects to save. By sending 0 as the number of layers it means we want all nested layers
                        // (which will include our Controller Test module), and by sending the top module test it means store everything and all child wires / registers.
  end
 
  // This creates a blank module with a clock that flips once per frame and we setup the simulation to end after 1000 frames. The last block will output anything defined in 
  // this module into a VCD file.
  //
  // So next we only need to instantiate our controller and we will be able to test it:
  reg req1 = 1, req2 = 1, req3 = 1;
  wire [2:0] grantedAccess;
  wire enabled;

  wire [7:0] address;
  wire [31:0] dataToMem;
  wire readWrite;

  reg [7:0] addr1 = 8'hA1;
  reg [7:0] addr2 = 8'hA2;
  reg [7:0] addr3 = 8'hA3;

  reg [31:0] dataToMem1 = 32'hD1;
  reg [31:0] dataToMem2 = 32'hD2;
  reg [31:0] dataToMem3 = 32'hD3;


  memController fc(
    clk,
    {req3, req2, req1},
    grantedAccess,
    enabled,
    address,
    dataToMem,
    readWrite,
    addr1,
    addr2,
    addr3,
    dataToMem1,
    dataToMem2,
    dataToMem3,
    1'b0, 
    1'b1, 
    1'b0 
  );

// We go through creating all the registers and wires required to instantiate our controller. We won't really have modules using the shared memory, so in terms of address we will 
// use a static address to simulate this, same for the data we will just hardcode a value.
//
// Next to really test the requeing we need a way to simulate a module releasing access once granted and then to re-request access making it get re-added to the queue. We can do this
// by just adding a counter for example we will count 4 frames and then release the shared resource:
reg [1:0] counter = 0;
always_ff @(posedge clk) begin 
  if(enabled) begin 
    counter <= counter + 1;
    if(counter == 2'b11) begin 
      if(grantedAccess == 3'b001) begin 
        req1 <= 0;
      end else if (grantedAccess == 3'b010) begin 
        req2 <= 0;
      end else if (grantedAccess == 3'b100) begin 
        req3 <= 0;
      end
    end
  end else begin 
    counter <= 0;
    req1 <= 1; 
    req2 <= 1; 
    req3 <= 1;
  end
end 

// So when the 'enabled' wire is high, we count up four frames and then set the corresponding request bit to zero. Otherwise in-between when modules are currently granted access we reset
// all request bits to 1.
//
// We could have shortened this by having the request bits be a single register and using the same method as we used in the controller for setting unsetting 'currentlyInQueue', but I think 
// this allows for better visualization when viewing the VCD file as we can see each bit separated on its own line.
endmodule

// You can compile and run this with the following commands:
// iverilog -o controller_test.o -s test controller.v controller_tb.v
// vvp controller_test.o
// You should then see a VCD file called controller.vcd. Looking through this file we can see that everything seems to be working great:

