/* Now before running this on the FPGA let's look at the first form of 
 * debugging which is simulation and visual logic debugging. */

/* To get started we need to create another verilog module known as a test bench which 
 * will define the simulation. So create another verilog file called uart_tb.v with a 
 * new module: */

/* So here we are creating a register for the clock the uart rx and tx pins the wires and the button.
 * This isn't always true but as a general rule of thumb I use registers if it is an input into the 
 * module to drive the value and if it is an output I use a wire as the module itself will drive the value. */
module test();
  reg  clk = 0;
  reg  uart_rx = 1;
  wire uart_tx;
  wire [5:0] led;
  reg  btn = 1;

/* You can also see that we are defining an override for the DELAY_FRAMES parameter. The #() is for the parameters 
 * and we don't want to actually need to look at 234 frames of clock pulses in our simulation so I lowered it to 
 * 8 clock pulses. */
uart #(8'd8) u(
    .EXT_CLK(clk),
    .BTN_S1(btn),
    .UART_RX(uart_rx),
    .UART_TX(uart_tx),
    .LED_O(led)
);

/* Next we need a way to simulate the clock signal. This can be done like follows:
 * The #number (#1) is a special simulation syntax from iverilog that allows us to delay
 * something by a certain number of time frames. By saying each time interval the clock 
 * alternates, we are saying the clock cycle is 2 time units (1 high cycle and 1 low 
 * cycle is 1 clock cycle). So this loop will wait 1 time unit and toggle the clock
 * register. */
always 
  #1 clk = ~clk;

/* The next simulation specific feature I want to go over is the $display and $monitor 
 * commands. They are similar to a printf or console.log where they print out a string 
 * optionally injecting variables into it. The difference between display and monitor, 
 * is that display will only print the value out once, monitor will print it out, and 
 * then reprint it out any time the value changes. */
// So to simulate the UART transmission we can do the following:
initial begin 
  $display("Starting UART RX");
  $monitor("LED Value %b", led);
  #10 uart_rx=0; // Initially pull the UART-RX line low - insert START BIT 
  #16 uart_rx=1; // inject UART DATA - BIT #0
  #16 uart_rx=0; // inject UART DATA - BIT #1
  #16 uart_rx=0; // inject UART DATA - BIT #2
  #16 uart_rx=0; // inject UART DATA - BIT #3
  #16 uart_rx=0; // inject UART DATA - BIT #4
  #16 uart_rx=1; // inject UART DATA - BIT #5
  #16 uart_rx=1; // inject UART DATA - BIT #6
  #16 uart_rx=0; // inject UART DATA - BIT #7
  #16 uart_rx=1; // inject STOP BIT - 
  #1000 $finish;
end

/* We start by printing a message, then we track the values of the leds and inject
 * their value by using the %b which means print the binary representation of this field.
 * After that we send the start bit by pulling the line low, then send 8 data bits and 
 * finally the stop bit. We delay by 16 time frames or 8 clock cycles as that is what we 
 * set DELAY_FRAMES (instantatiated as the parameter to the uut block) to be. */
 
/* For visually debugging the logic we can add another block to dump a VCD file. */ 
initial begin 
  $dumpfile("uart.vcd");
  $dumpvars(0,test);
end 
/* $dumpfile chooses the name of the file, and $dumpvars choosing what to save and how many
 * levels of nested objects to save. By sending 0 as the number of layers it means we want 
 * all nested layers (which will include our uart module), and by sending the top module 
 * test it means store everything and all child wires / registers. */

endmodule

/* Terminal commands that call iVerilog */
// iverilog -o uart_test.o -s test uart.v uart_tb.v
// vvp uart_test.o

/* The first line generates a simulation based on the verilog files we sent it, the -s sets
 * what is the top or main module being run and -o sets the simulation executables name. 
 * Once done the second line runs the simulation and it will produce the following output: 
 * 
 * Starting UART RX
 * VCD info: dumpfile uart.vcd opened for output.
 * LED Value xxxxxx
 * LED Value 011110
 */