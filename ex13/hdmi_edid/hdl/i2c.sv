// < The Implementation >
//
// In a new folder in VSCode let's start off by creating our building blocks by implementing the I2C physical layer. To do this let's create a new file called i2c.v with the following module:
`default_nettype none

module i2c
#(
  parameter MAIN_CLK_FREQ_HZ = 32'd27000000 // The main clock frequency that is utilized
)
(
  input wire       clk,  // The main clock signal.
  // I2C SDA - relies on each side both being able to read and write to the same wire.
  input wire       sdaIn, // first of the three registers for the I2C SDA line - being a bidirectional interface on a single line - this is for its input part.
  output reg       sdaOut = 1, // second of the three registers for the I2C SDA line - being a bidirectional interface on a single line - this is for its output part. Init (idle) output part for SDA high ('1') level. 
  output reg       isSending = 0, // third of the three registers for the I2C SDA line - being a bidirectional interface on a single line - this is the SDA as input/output selector.
                                 // Init (idle) state at - '0'. Meaning: '1' - if we're writing data; set to '0' - if we're reading data 
  output reg       scl = 1, // we have an output wire for SCL here we are not using a tristate buffer and simply an output wire since we don't need to support clock-stretching in our use-case. Idle at high ('1') level.
  input wire [1:0] instruction, // Next we receive a 2 bit instruction, this will represent which of the 4 sub-tasks (instructions) we currently would like to perform from: 
                                // 1. Start I2C; 2. Stop I2C; 3. Read Byte + Ack; 4. Write Byte + Ack
  input wire       enable, // enable pin, for an outside module to trigger the module to perform the current instruction chosen (as opposed to being idle).
  input wire [7:0] byteToSend, // an 8-bit value to send (in the event of a write byte instruction).
  output reg [7:0] byteReceived = 0, // a buffer to be used to output a byte, when the 'read byte' instruction was used.
  output reg       complete = 0 // a wire so that the i2c module can let the (outside) module using it, know that the instruction is complete and it can move onto the next instruction. Init (default) to 0
);

// Now let's create our states for the module's state machine:
// - We start with our 4 instructions (subtasks) so that their index matches what will be in the 'instruction' input. 
localparam INST_START_TX = 0;
localparam INST_STOP_TX = 1;
localparam INST_READ_BYTE = 2;
localparam INST_WRITE_BYTE = 3; 
// - Then we have our states: 
localparam STATE_IDLE = 4; // we have an idle state which is the default state when no-one is communicating over I2C. 
localparam STATE_DONE = 5;  // The done state is for letting the external module who executed an I2C instruction that the instruction is complete.
localparam STATE_SEND_ACK = 6; // The last two states are continuations of the read - when reading we need to send an ACK - ...
localparam STATE_RCV_ACK = 7; // ... and write instructions -  and we writing we need to receive an ACK.

// Next we will need 3 registers:
// By default the ADS1115 supports up to 400 kHz communication, there is also a high-speed 3.4 MHz mode but you have to enable it. We will be using the standard mode so we will need to divide our 27MHz clock down to something under 400 kHz.
reg [6:0] clkDivider = 0; // we divide the main clock by 128 (or 2^7) then we get a little over 200 kHz and its a power of 2 making it easier to work with. So because of this we will create a 7-bit register which will count clock cycles.
reg [2:0] state = STATE_IDLE; // a register to hold the current state, we will default to the idle state.
reg [2:0] bitToSend = 0; // register to count which bit of a byte we are on, some of the states like sending or receiving are based around a byte of data, so we will use 'bitToSend' to remember which bit we are on.

// Next we need an always block for our state machine:
always_ff @(posedge clk) begin 
  case(state)  // < The I2C States >
    STATE_IDLE: begin  // The first state we will implement is the idle state ...
      if(enable) begin  // ... here we just wait until the enable pin is pulled high in which case we will start performing the operation passed in.
        complete <= 0; // set 'complete' low since we are starting a new operation,
        clkDivider <= 0;  // we reset our two counter registers and  ...
        bitToSend <= 0; 
        state <= {1'b0, instruction}; // ... we jump to the state matching the instruction number.
      end
    end
    INST_START_TX: begin // the I2C start condition which is when both clock and data lines are high and we pull the data line down before pulling the clock line down.
      isSending <= 1; // setting the 'isSending' flag high to take control over SDA ...
      clkDivider <= clkDivider + 1; // ... and we start counting clock cycles.
      // We then divide the entire SCL clock time (~200 kHz) into 4 equal sections by looking only at the top two bits.
      if(clkDivider[6:5] == 2'b00) begin // During Q1: In the first section both lines (SCL and SDA) are high, ...
        scl <= 1;
        sdaOut <= 1;
      end else if(clkDivider[6:5] == 2'b01) begin // During Q2: we then pull SDA low (while SCL line is being high) ...
        sdaOut <= 0;
      end else if(clkDivider[6:5] == 2'b10) begin // During Q3: ... followed by pulling the SCL line low. We wait one more period and ... 
        scl <= 0;
      end else if(clkDivider[6:5] == 2'b11) begin // Beginning Q4: ...  then move to the done state.
        state <= STATE_DONE; // We wait one more period before completing the instruction so that we stop in-between the low-clock pulse of SCL just like we blocked out in the image when above.
      end
    end
    INST_STOP_TX: begin  // The next state / instruction is the stop condition state, it is exactly like the start just reversed:
      isSending <= 1;
      clkDivider <= clkDivider + 1;
      if(clkDivider[6:5] == 2'b00) begin // During Q1: Both lines start off low ... 
        scl <= 0;
        sdaOut <= 0;
      end else if(clkDivider[6:5] == 2'b01) begin // During Q2: // ... we first pull the SCL high ... 
        scl <= 1;
      end else if(clkDivider[6:5] == 2'b10) begin // During Q3: // ... only after that we pull the SDA high (in the middle SCL being high). We wait one more period before completing the instruction ...
        sdaOut <= 1;
      end else if(clkDivider[6:5] == 2'b11) begin // Beginning Q4: ...  then move to the done state.
        state <= STATE_DONE; 
      end
    end
// Another way of looking at this value ('clkDivider') is that the top two bits ('clkDivider[6:5]') are the quarter index and the rest are the sub-quarter counter. So we want quarter 10 which is 2 in decimal which represents the 
// 3rd quarter (index starts at 0) and if all the other bits are zero then we are at the beginning of this quarter.
    INST_READ_BYTE: begin // The next instruction is to read a byte of data: This is the first state where we are setting not controlling the SDA line and we will instead be using it as an input.
      isSending <= 0;                                                                                                   
      clkDivider <= clkDivider + 1;                                                                                     
      if(clkDivider[6:5] == 2'b00) begin // During Q1: we have the first quarter cycle with the SCL low,                                                                  //      Taking a look at the 4 quarters of our SCL cycle:           
        scl <= 0;                                                                                                                                                         //                             .  .  .  .  .
      end else if(clkDivider[6:5] == 2'b01) begin  // During Q2: in the second quarter we set the SCL high.                                                               // CLOCK (SCL) : '1'           .  +-----+  .          
        scl <= 1;                                                                                                                                                         //                             .  |  .  |  .           
      end else if(clkDivider == 7'b1000000) begin // At start of Q3: we want to read, exactly in the middle of the clock cycle - when 'clkDivider' equals 7'b1000000.     //               '0'       -------+  .  +-------         
        byteReceived <= {byteReceived[6:0], sdaIn ? 1'b1 : 1'b0}; // Shift-in the value of SDA into 'byteReceived' - MSb first                                            //                             .Q1.Q2.Q3.Q4.              
      end else if(clkDivider == 7'b1111111) begin // Right at end of Q4:                                                                                                  //                             .  .  .  .  .
        bitToSend <= bitToSend + 1;   //  we have completed a single bit,                                                                                                 //  DATA (SDA)   '1'           +-----------+         
        if(bitToSend == 3'b111) begin     // we check if we are already on the last bit, ...                                                                              //               '0'       ----|    DATA   |----          
          state <= STATE_SEND_ACK;   // ... if so we move onto the ACK                                                                                                    //                             .  .  .  .  .
        end // otherwise we just continue which will cause 'clkDivider' to overflow back to zero starting the cycle over for the next bit.                                //                             .  .  .  .  .
      end else if(clkDivider[6:5] == 2'b11) begin  // The last condition is what to do in the rest of Q4 (overall) and that is to pull the clock low                      //                             .  .  .  .  .
        scl <= 0;                                                                                                     
      end 
    end
    STATE_SEND_ACK: begin // To send the ACK we just need to hold SDA low and pulse 1 SCL clock cycle:
      isSending <= 1; // While sending the ACK we retake control over SDA by setting 'isSending' high,
      sdaOut <= 0; // we also set 'sdaOut' low to send the low ACK signal. 
      clkDivider <= clkDivider + 1;
      if(clkDivider[6:5] == 2'b00) begin // During Q1: SCL clock low
        scl <= 0;
      end else if(clkDivider[6:5] == 2'b01) begin  // During Q2: SCL clock pulse, going high 
        scl <= 1;
      end else if(clkDivider == 7'b1111111) begin // At end of Q4:  move to the done state.
        state <= STATE_DONE;
      end else if(clkDivider[6:5] == 2'b11) begin //During Q4: SCL clock pulse, going low
        scl <= 0;
      end
    end 
    INST_WRITE_BYTE: begin // With the reading of a byte complete, writing a byte is pretty much at least in structure:
      isSending <= 1;
      clkDivider <= clkDivider + 1;
      sdaOut <= byteToSend[3'd7-bitToSend] ? 1'b1 : 1'b0; // We set 'sdaOut' to the corresponding bit we currently want to send starting with bit index 7 or the MSb.
      //  The rest is pretty much just to clock an SCL clock cycle and ...
      if(clkDivider[6:5] == 2'b00) begin // During Q1: SCL clock low
        scl <= 0;
      end else if(clkDivider[6:5] == 2'b01) begin  // During Q2: SCL clock high
        scl <= 1;
      end else if(clkDivider == 7'b1111111) begin // At end of Q4: 
        bitToSend <= bitToSend + 1;
        if(bitToSend == 3'b111) begin // ... we have the condition for the end of Q4 to see if we have completed all 8 bits.
          state <= STATE_RCV_ACK;
        end
      end else if(clkDivider[6:5] == 2'b11) begin // During Q4: SCL clock low
        scl <= 0;
      end 
    end
    STATE_RCV_ACK: begin  // While receiving the ack we need to clock out an SCL clock pulse and theoretically during the high part of the clock pulse we should see that the peripheral pulled the SDA line low. 
      isSending <= 0;
      clkDivider <= clkDivider + 1;
      if(clkDivider[6:5] == 2'b00) begin // During Q1: SCL clock low
        scl <= 0;
      end else if(clkDivider[6:5] == 2'b01) begin  // During Q2: SCL clock high
        scl <= 1;
      end else if(clkDivider == 7'b1111111) begin // At end of Q4:
        state <= STATE_DONE;
      end else if(clkDivider[6:5] == 2'b11) begin // During Q4: SCL clock low
        scl <= 0;
      end //
      // We won't really be checking it, which is why I left it as a comment since we won't really be handling that case so there is no point checking it.  If you do want to handle it then you need to decide what happens if an error 
      // was detected, like for example sending an end condition over I2C and setting an error flag instead of complete to let the upper modules know their was an issue and retry or something.
      // else if (clkDivider == 7'b1000000) begin 
      //   sdaIn should be 0
      // end
    end
    STATE_DONE: begin // The final state is the done state where we only let the external module know the I2C instruction is complete and we wait for them to acknowledge by releasing the enable input, this way we have two way validation.
      complete <= 1;
      if(~enable)
        state <= STATE_IDLE;
    end
  endcase
end
// With that we have our 4 I2C building blocks and we can move onto building the ADC module.
endmodule
