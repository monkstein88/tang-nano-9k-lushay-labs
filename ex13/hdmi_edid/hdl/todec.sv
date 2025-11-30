// Convert Binary number to Decimal representation - Double Dabble method
module toDec( // We receive as input: 
  input wire clk, // the clock and ...
  input wire [11:0] value, // ... the (binary) value we want to convert. then we output ... (ADS1115 ADC value)
  output reg [7:0] thousands = " ", // ... 4 ASCII characters 1 for each digit.
  output reg [7:0] hundreds = " ", 
  output reg [7:0] tens = " ",
  output reg [7:0] units = "0"
);

reg [15:0] digits = 0; // a register for the digits which like we saw above we need 4 per digit so here we have 16 bits, we will be shifting the value into here.
reg [11:0] cachedValue = 0; // a register to cache the value. This conversion process happens over multiple clock cycles so we don't want the number we are converting to change in the middle,
reg  [3:0] stepCounter = 0; // a register to store which shift iteration we are, because our input value is 12 bits wide, we need to perform the add3 + shift steps 11 times to convert the full number,
reg  [3:0] state = 0; // a register  to hold our current state in the conversion state machine.

localparam START_STATE = 0; // Starting state - here we need to cache value & reset registers
localparam ADD3_STATE = 1; // Add 3 - here we check if any of the 4 digits in the 16 bits need us to increment them by 3. 
localparam SHIFT_STATE = 2; // Shift - here we shift the cached value into the digits register.
localparam DONE_STATE = 3; // Done - here we store the results in our output buffers in ascii format.

always_ff @(posedge clk) begin 
  case(state)
    START_STATE: begin 
      cachedValue <= value; // store 'value' to 'cachedValue' to lock it for the rest of the calculation.
      stepCounter <= 0; // initializes the counter and ... 
      digits <= 0; // ... digits register to 0
      state <= ADD3_STATE; //  From here we go to ADD3_STATE (we could have skipped it since on the first iteration none of the digits require adding 3, but to keep the order I go there next).
    end 
    ADD3_STATE: begin  // In this state we check for each of the 4 digits if they are over 5, if so we add 3 to that digit.
      digits <= digits +
                ((digits[3:0] >= 5)? (3 << 0) : 0) + // For the first digit the value is actually 3, ... 
                ((digits[7:4] >= 5)? (3 << 4) : 0 << 0) + // ... for the second digit we need to shift 3 four decimal places resulting in 48, ...
                ((digits[11:8] >= 5)? (3 << 8) : 0 << 0)+ // ... and shifting 48 another 4 decimal places gives us 768, ... 
                ((digits[15:12] >= 5)? (3 << 12) : 0 << 0); // ... and shifting 768 another 4 decimal places gives us 12228.
      state <= SHIFT_STATE;
    end 
    SHIFT_STATE: begin 
      digits <= {digits[14:0], cachedValue[11]}; // First, shift digits over by 1 to the left, losing bit 15, but inserting bit 11 of our cached value
      cachedValue <= {cachedValue[10:0],1'b0}; // We also then shift cachedValue to remove bit 11 since we already "dealt" with it.
      if(stepCounter == 11) // If stepCounter equals 11 it means we have already shifted all 12 times and we can move onto the done state, otherwise ... 
        state <= DONE_STATE;
      else begin  // ... we increment the counter and go back to the add 3 state to continue the algorithm.
        state <= ADD3_STATE;
        stepCounter <= stepCounter + 1;
      end 
    end 
    DONE_STATE : begin
      thousands <= "0" + digits[15:12]; 
      hundreds <= "0" + digits[11:8];
      tens     <= "0" + digits [7:4];
      units    <= "0" + digits [3:0];
      state <= START_STATE; // ... then goes back to the first starting state to get the new updated value and start converting it.
    end 
  endcase
end
// The only difference here is that we added another digit extra so that we can display the voltage as 4 digits.
endmodule // toDec
