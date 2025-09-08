module top
(
  input EXT_CLK,
  output [5:0] LED_O
);

localparam WAIT_TIME = 13500000;
reg [5:0] ledCounter = 0;
reg [23:0] clockCounter = 0;
/*
It is also worth noting that the <= operator is not like a standard assignment operator from most programming languages. 
This operator sets the value for the input of the flip-flop which will only propagate to the output on the next clock signal. 
This means that even though we increment it on the first line of the block, the value of clockCounter will only equal 1 on 
the next clock pulse, and for the remainder of the current block the value will still be 0. Same thing when we increment the ledCounter, 
The change will only be seen on the next clock signal.

There is a way to immediately assign a value using the blocking = operator instead, but I like to stick only with the non-blocking 
assignment operator <= when working with registers, both for simplicity, consistency and I think it is a better practice.
*/
always @(posedge EXT_CLK) begin
    clockCounter <= clockCounter + 1;
    if (clockCounter == WAIT_TIME) begin
        clockCounter <= 0;
        ledCounter <= (ledCounter + 1);
    end
end

/* 
The last and final thing to finish our verilog module is to connect the value of our register to the leds.
Outside the always block we use the assign and = to define the value of wires. Wires (which is the default input/output type) 
unlike registers don't store values so we need to simply define what they are connected to and they will always equal that value 
(since they will be physically connected to them).

The only thing is that the counter is inverted. This is due to the fact that the LEDs use a common anode and a value of 0 means
to light up not a value of 1. To fix this we can make a small change to our code.

To update the verilog code in our example invert the counter so that the leds match the bit status using the ~ operator.
The final line of our module should be:
*/
assign LED_O = ~ledCounter;

endmodule