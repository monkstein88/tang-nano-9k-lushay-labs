// < The Controller >
//
// The type of arbiter we will be making is a basic queue based controller where up to 3 modules can request access to the shared resource and we will allow for multiple commands 
// to be performed before releasing.
//
// To get started let's create a new file called controller.v with the following empty module:
`default_nettype none

module memController
(
  input wire clk, 

  input wire [2:0] requestingMemory,
  output reg [2:0] grantedAccess = 0,
 
  output reg enabled,
  output reg [7:0] address, 
  output reg [31:0] dataToMem, 
  output reg readWrite,  

  input wire [7:0] addr1,
  input wire [7:0] addr2,
  input wire [7:0] addr3, 

  input wire [31:0] dataToMem1,
  input wire [31:0] dataToMem2,
  input wire [31:0] dataToMem3, 
 
  input wire readWrite1,
  input wire readWrite2,
  input wire readWrite3
);

// The first 3 ports are the actual ports required to create the arbiter, the rest of the connections are to actually control the bus to the shared memory. Basically we have 3 input
// bits called requestingMemory, one for each module that wants to use the shared resource and we have an output called grantedAccess which will store the bit of the module who is 
// currently in control.
//
// So for example the first module will get bit 0 the second bit 1 and the third bit 2. requestingMemory can hold values like the following:
// 3'b011
// 
// meaning that both module 1 and module 2 are requesting the shared resource and module 3 is not. The output grantedAccess on the other hand will only have a single bit active at a
// time. So for example if module 2 is currently the module in control of the shared resource then grantedAccess will be:
// 3'b010
//
// The next 4 ports comprise the output bus to the shared resource, you can notice that we don't include dataFromMem here as all modules can share those lines since there is only a 
// single driver (the shared memory) as opposed to dataToMem where we have 3 drivers (the 3 modules requesting access) so they need to be muxed.
//
// The rest of the ports are just the different options we can connect to the output, so for example addr1 is the address from module 1 and addr2 is the address from module 2 and so
// on. The same for dataToMem and the readWrite flag. Basically based on who is granted access we will connect the corresponding modules inputs to the outputs going to the shared 
// memory.
//
// So our module has two roles, one is to decide who is granted access, and the other role is to connect the wires based on who has access acting as the bus controller.
//
// Just as a side note, these two roles can be separated, so you can have a more general purpose arbiter which only has the first 3 ports here, so it only outputs who is currently 
// grantedAccess based on the requests, and then have a separate module which takes that info and controls the connection to the shared memory.
//
// Next let's create some registers inside:
reg [2:0] queue [0:3] = '{default:'0}; // 3-bits wide - [2:0], 4 counts [0:3]
reg [2:0] currentlyInQueue = 0;
reg [1:0] queueNextIndex = 0; // for indexing of 4
reg [1:0] queueCurrIndex = 0; // for indexing of 4

// We start by creating a register for our queue, we use 3 bits to store a module number like grantedAccess (so each bit represents a different module) and we make 4 places as we 
// need at least 3 spaces and it's better to have a power of 2 so that the index registers will roll over automatically making them circular.
//
// The next register 'currentlyInQueue' will store whether or not one of the modules is already in the queue. This is in the format of 'requestingMemory' where each bit is a different
// module and they can all be 1 at the same time.
//
// Finally to implement a circular fifo queue we need to indices, one for each end of our queue. The first index is queueNextIndex which represents the next index where we should place
// a value, this is the end of our queue, and we have queueCurrIndex which is the first value in the queue (the one we will be giving access to) so they represent the two edges of the 
// queue.
//
// When we insert a new value into the queue we increment 'queueNextIndex' and when we use a value from the beginning of the queue we increment 'queueCurrIndex'. If the two indices are 
// equal it means the queue is empty, and because we chose a power of 2 as the queue size we don't need to handle wrapping around to the beginning in our circular queue, it will happen
// automatically.
//
// Next let's add two "helper" wires which we can use to simplify the modules task:
wire [2:0] requestsNotInQueue; // 'requestsNotInQueue' is basically the opposite of 'currentlyInQueue' but with the trait - they are requesting access.
wire [2:0] nextInLine; // 'nextInLine' will store one out of the possible 3 modules requesting access 
// 'requestsNotInQueue' is basically the opposite of 'currentlyInQueue' just with an extra check to make sure they are requesting access, for example module 2 might not be in the queue,
// but it may not want to be in the queue so we filter for only requesting modules. 'nextInLine' will store one out of the possible 3 modules requesting access as we can only handle 1 
// request at a time.
//
// We can already assign these two wires as follows: 
assign requestsNotInQueue = (requestingMemory & ~currentlyInQueue); // get a list of modules not in the queue, but that want to be in the queue.
assign nextInLine = requestsNotInQueue[0] ? 3'b001 : requestsNotInQueue[1] ? 3'b010 : 3'b100; // is simply the first bit that is currently requesting and not in the queue. 
assign enabled = grantedAccess[0] | grantedAccess[1] | grantedAccess[2]; // is high if control to the shared resource is currently granted to one of the 3 modules,
// Like I mentioned we flip 'currentlyInQueue' and '&' it with the modules requesting access to get a list of modules not in the queue but that want to be in the queue.
// 
// 'nextInLine' is simply the first bit that is currently requesting and not in the queue. Again this is because in our module we can only add a single request to our queue per clock 
// cycle, so at each iteration we need only a single requester, this is what is stored in 'nextInLine'.
//
// Finally 'enabled' is high if control to the shared resource is currently granted to one of the 3 modules, we OR all the bits together, this is the same as checking whether it doesn't
// equal zero.
//
// Now let's handle adding someone to the queue:
always_ff @(posedge clk) begin 
  if(requestsNotInQueue != 0) begin 
    queue[queueNextIndex] <= nextInLine;
    currentlyInQueue <= currentlyInQueue | nextInLine;
    queueNextIndex <= queueNextIndex + 1;
  end else if(enabled && (requestingMemory & grantedAccess) == 0) begin 
    grantedAccess <= 3'b000;
    queueCurrIndex <= queueCurrIndex + 1;
    currentlyInQueue <= currentlyInQueue & (~grantedAccess);
  end
  if(~enabled && queueNextIndex != queueCurrIndex) begin 
    grantedAccess <= queue[queueCurrIndex]; 
  end 
end 
// On each clock cycle we see if there are modules requesting access that are still not in the queue using our helper wire we just hooked up. If there is we place 'nextInLine' which is 
// one of the three modules (e.g. 3'b010 for module 2) and we place it in the queue at the next available index.
//
// The next line sets the module's corresponding bit in 'currentlyInQueue' to 1 so that it won't be added again to the queue and finally we increment 'queueNextIndex' to point at the 
// next available index where a request should be added.
//
// Next let's add the code to remove a request from the queue when someone releases control.
//
// The first condition is if 'enabled' is high, which is the same as saying, if access is currently being granted to someone. The second condition is to check that the person currently 
// granted access is no longer requesting access. By 'ANDing' the bit of the current module controlling the shared memory with the requests we isolate that specific bit, and then if it 
// equals zero we know they released control.
// 
// So if we are currently granting access to someone and they have stopped requesting access, we will remove them from the queue by incrementing 'queueCurrIndex'. We also set 
// 'grantedAccess' to zero removing the access from this module, and we unset the bit from 'currentlyInQueue' corresponding to this module.
//
// The reason this is in an else if, instead of happening in parallel, is because they both are setting values for 'currentlyInQueue' which will cause verilog to take the last update if 
// both were to happen losing data of a module being added to the queue. So we can either add a new module request to the queue or remove a request from the queue, not both at the same
// time.
//
// The final section in our always block is to actually give access to the module at the start of our queue. So if we are currently not giving access to anyone, and the two indices for 
// next available and current queue item are not equal (which would signify an empty queue) then we can give the next in line access.
//
// This can happen in parallel to adding / removing module requests from the queue.
//
// With that the only thing left to do here is to actually mux the wires to the shared memory based on who is currently 'grantedAccess'. So at the bottom of our module (outside the 
// always block) add the following:
assign address  = (grantedAccess[0]) ? addr1 :
                  (grantedAccess[1]) ? addr2 :
                  (grantedAccess[2]) ? addr3 : 0; 

assign readWrite = (grantedAccess[0]) ? readWrite1 :
                   (grantedAccess[1]) ? readWrite2 :
                   (grantedAccess[2]) ? readWrite3 : 0; 

assign dataToMem = (grantedAccess[0]) ? dataToMem1 :
                   (grantedAccess[1]) ? dataToMem2 :
                   (grantedAccess[2]) ? dataToMem3 : 0;
// For each of the ports we need to mux, we simply check which bit is currently high and based on that connect output to the corresponding modules input.
endmodule

// We should now have a working arbiter which will allow for up to 3 modules to share our memory module we created. Now before building an example let's create a testbench so that we
// can visually verify that the controller is working.