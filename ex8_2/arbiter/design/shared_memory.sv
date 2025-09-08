 // < The Implementation >
//
// Before we get into the actual controller, we need a shared resource. For this tutorial let's create a module to act as our shared storage. Arbitrarily let's make each position in memory be 4 bytes long
// (or 32-bits) and let's make there be 256 positions so that the address fits in a single byte.
`default_nettype none 

module sharedMemory
(
  input wire clk, // the clock source 
  
  input wire [7:0] address,  // an 8-bit address line
  input wire readWrite,      // flag which tells us if we are currently reading or writing (1 = read and 0 = write).
  output reg [31:0] dataOut = 0, //  we have two 32 bit registers, one for data out or data being read from memory, ...
  input wire [31:0] dataIn, // ...  and one for data in which is data being written to memory.
  input wire enabled // enable pin to tell the shared memory we are performing an action currently. There are some clock cycles where we both don't want to write or read, so this extra wire will tell it
                // we are now performing an operation otherwise the shared memory can be idle.
);

// Next let's create the storage itself inside:
reg [31:0] storage [0:255]; // creates our memory called storage which like we said has 256 positions each of which with 32-bits.
// Just to initialize the value of the memory to 0 and is not synthesized as part of the actual bitstream.
integer i; 
initial begin 
  for(i = 0; i < 256; i = i+1) begin 
    storage[i] = 0;
  end 
end 

// Finally the actual logic of the module:
always_ff @(posedge clk) begin 
  if(enabled) begin 
    if(readWrite) begin 
	    dataOut <= storage[address];
	  end else begin 
	    storage[address] <= dataIn;
	  end 
  end 
end 

// Basically we wait for the 'enable' pin to go high, then we perform an operation on every clock cycle, if the 'readWrite' flag is high, we read the 32-bits stored at the requested 'address' and store it
// in 'dataOut' and if the flag is low we write 'dataIn' into memory at the requested 'address'.
//
// To use this module you would basically need to set the address, readWrite flag and dataIn input (for write operations) and then enable the memory. In this design both read and write operations take a 
// single clock cycle, so when enabled one could change all the inputs on each clock cycle to perform a different operation. 
//
// This memory module is a single port memory, meaning it expects only a single "user" at a time. So if we have multiple modules relying on this memory we need to synchronise between them on our own. 
// So let's now start building our controller.

endmodule