// Generalizing the LFSR Module
// The difference between all LFSRs of this type (fibonacci / external LFSRs) is the size of the register (num bits) the tap configuration, and some would say the initial seed.
// Changing the seed doesn't change the sequence, it just changes where you start in the sequence, but we can say that this is another difference.
// Other then that we still just need to create a register shift the bits over and calculate the new bit based on the taps chosen.
// Let's create a file called lfsr.v with a module accepting these as parameters:

`default_nettype none 

module lfsr 
#(
  parameter SEED = 5'd1,
  parameter TAPS = 5'h1B,
  parameter NUM_BITS = 5
)
(
  input  wire clk,
  output reg  randomBit 
);
  reg [NUM_BITS-1:0] sr = SEED; //  create a register of the desired size holding our seed value as it's initial value
  wire finalFeedback; // a wire which will hold the feedback after the feedback calculation (XORs). 
  
  always_ff@(posedge clk) begin   // The calculation each clock cycle:
    sr <= {sr[NUM_BITS-2:0], finalFeedback}; // shifting all the bits up 1 and putting our feedback bit into b0.
    randomBit <= sr[NUM_BITS-1]; // output bit
  end
  
  // How do we XOR the bits from our taps to generate the final feedback bit.
  // We can simply go over all bits and either XOR them or XOR a zero, XOR-ing a zero doesn't affect the output, its like multiplying by one.
  // we will chain each bit with the value of the previous bit's feedback XOR-ed either with it or with a zero if it is not a tap. 
  genvar i;
  generate  //  "generate" repetitive verilog code using loops instead.
    for(i=0; i < NUM_BITS; i = i+1) begin: lf   // So we loop over all the bits storing the current index inside i, we also name this loop lf (linear feedback) so that we will have a reference to access any wires or registers defined inside.
      wire feedback; // In each iteration of the loop we create a feedback wire and we connect it to one of two things. 
      if(i==0) // If we are on the first bit, there is no previous bit, so we simply take the current bit (sr[i]) AND-ed together with the same bit from the TAP parameter.
        assign feedback = sr[i] & TAPS[i]; // What this is doing is either evaluating to the value of current bit sr[i] if the TAP bit is 1, or making these two evaluate to zero if the TAP is not part of the XOR equation. By making it zero it won't affect the XOR operation.
      else
        assign feedback = lf[i-1].feedback ^ (sr[i] & TAPS[i]); // For all the other bits we take the previous feedback and XOR it with the same AND equation to either make it a zero if it is not part of our XOR equation, or return the value of sr[i].
    end
  endgenerate 
  assign finalFeedback = lf[NUM_BITS-1].feedback; // Take the output of the (last) XOR-ing. Connect the feedback from the final iteration to the wire we created finalFeedback: 
  // With that we now have a fully working LFSR of any size and any tap configuration.
endmodule