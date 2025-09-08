// < Using the Shared Memory >
//
// We created a module already which holds are shared memory, and now we have the arbiter ready to allow for sharing, the last piece we need is the modules who will be using the memory.
// Let's create a module which increments a value in memory, we can use this to double check we don't get any race conditions and that our controller can be used as a semaphore.
//
// To get started let's create a file called 'memory_inc.v' with the following module:
module memoryIncAtomic(
  input wire clk,
  input wire grantedAccess, 
  output reg requestingMemory = 0,
  output reg [7:0] address = 8'h18, 
  output reg readWrite = 1, 
  input wire [31:0] inputData,
  output reg [31:0] outputData = 0
);

// We want this module to increment a value in memory by 1 once a second. To interface with our controller we have an input for when this module has been granted control of the shared 
// resource and we have an output bit 'requestingMemory' to signal that we are requesting control of the shared resource.
// Other then that we have outputs for the desired 'address', 'read/write' flag and 'output data' to memory and then we have an input register which will have the 'data read' from memory.

// To start off with we can create a counter to count if a second has passed:
reg [24:0] counter = 0;
always_ff @(posedge clk) begin
  if(grantedAccess)
    counter <= 0;
  else if(counter != 25'd27000000) 
    counter <= counter + 1;
end
// We reset the counter whenever we are in control, and once we release control we start counting stopping when we reach 27,000,000 clock cycles which equals 1 second.

// Next we will need a state machine so let's define our states:
reg [1:0] state = 0;
localparam STATE_IDLE = 2'd0; 
localparam STATE_WAIT_FOR_CONTROL = 2'd1; 
localparam STATE_READ_VALUE = 2'd2; 
localparam STATE_WRITE_VALUE = 2'd3; 

// The first state is the idle state here we are waiting for a second to pass, once we have waited a second we will request control, but then we need to wait for the controller to grant us 
// access. This is what we will do in the second state, once in control of the shared resource we can read the current value and then write the new value back to memory.
// The implementation of these steps looks like this:
always_ff @(posedge clk) begin 
  case(state) 
    STATE_IDLE: begin 
      if(counter == 25'd27000000) begin 
        state <= STATE_WAIT_FOR_CONTROL;
        requestingMemory <= 1;
        readWrite <= 1;
      end
    end
    STATE_WAIT_FOR_CONTROL: begin 
      if(grantedAccess) begin
        state <= STATE_READ_VALUE; 
      end
    end
    STATE_READ_VALUE : begin 
      outputData <= inputData + 1;
      state <= STATE_WRITE_VALUE;
      readWrite <= 0;
    end 
    STATE_WRITE_VALUE : begin 
      requestingMemory <= 0;
      state <= STATE_IDLE;
      readWrite <= 1;
    end
  endcase
end 
// Like mentioned, the first state waits for the 'counter' to reach 1 second, we then move to requesting control of the memory and set the 'readWrite' flag to 1 to signify we want to read
// data. 
// In the second state we wait for 'grantedAccess' to go high, meaning we have received control and we then move onto the next state where we will store the value returned from memory (over
// 'inputData') incremented by 1 into 'outputData'. Besides for that in the next state we also set the 'readWrite' flag to zero to signify that now we want to write the data we put on 
// 'outputData' to memory.
//
// In the final state we basically just wanted another clock cycle to give the memory module a chance to write the data and then we can go back to the idle state releasing the shared resource
// by un-requesting the memory.
endmodule
// While here we can create a second module, exactly like this one except only for reading:
module memoryRead(
  input  wire clk,
  input  wire grantedAccess,
  output reg requestingMemory = 0,
  output reg [7:0] address = 8'h18,
  output reg readWrite = 1,
  input  wire [31:0] inputData,
  output reg [31:0] outputData = 0
);

reg [24:0] counter = 0;
always_ff @(posedge clk) begin 
  if(grantedAccess)
    counter <= 0;
  else if (counter != 25'd27000000) 
    counter <= counter + 1;
end

reg [1:0] state = 0;
localparam STATE_IDLE = 2'd0; 
localparam STATE_WAIT_FOR_CONTROL = 2'd1; 
localparam STATE_READ_VALUE = 2'd2; 

always_ff @(posedge clk) begin 
  case(state)
    STATE_IDLE: begin 
      if(counter == 25'd27000000) begin 
        state <= STATE_WAIT_FOR_CONTROL;
        requestingMemory <= 1;
        readWrite <= 1;
      end
    end
    STATE_WAIT_FOR_CONTROL: begin 
      if(grantedAccess) begin 
        state <= STATE_READ_VALUE;
      end
    end 
    STATE_READ_VALUE: begin 
      outputData <= inputData;
      state <= STATE_IDLE;
      requestingMemory <= 0;
    end
  endcase 
end
// Exactly the same just we only read and 'outputData' is not meant to go to the memory module, but rather to give the other modules the current value so we can display it.
endmodule 
// With that done we can now create our top module connecting all our other components.
