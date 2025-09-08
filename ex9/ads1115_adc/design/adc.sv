// < The ADC Module >
//
// To begin with let's create a new file called adc.v with the following module:
`default_nettype none 

module adc #(
  parameter address = 7'b0  // We start off with a parameter for the peripheral address which we need to send with each I2C command. 
)(
  // This will interract with the 'TOP' (ads1115_adc_top.sv):
  input  wire        clk,  //  we have the clock
  input  wire  [1:0] channel, // an input for which of the 4 ADC channels we want to read
  output reg  [15:0] outputData = 0, // a register for the 16-bit output data
  output reg         dataReady = 1, // one flag for this module to say when it has data ready
  input  wire        enable, // one flag for the top module to request a conversion 
  // The rest of the ports are the connections required to interface with the 'I2C' (i2c.sv) module we created:
  output reg   [1:0] instructionI2C = 0,
  output reg         enableI2C=0,
  output reg   [7:0] byteToSendI2C = 0,
  input  wire  [7:0] byteReceivedI2C,
  input  wire        completeI2C
);

// Next let's setup some things from the ADS1115 ADC data sheet. The setup register holds the values we want to put in the config register. The only thing that needs to be changed here is the channel each time depending 
// on which channel was requested. Setup config:
reg [15:0] setupRegister = {
  1'b1,     // Start Conversion 
  3'b100,   // Channel 0 Single Ended
  3'b001,   // FSR +- 4.096V
  1'b1,     // Single shot mode
  3'b100,   // 128 SPS
  1'b0,     // Traditional Comparator 
  1'b0,     // Active low alert 
  1'b0,     // Non latching 
  2'b11     // Disable comparator 
};
// The last two local parameters are what needs to be send in order to choose the respective register after sending an I2C write command.
localparam CONVERSION_REGISTER = 8'b00000000;
localparam CONFIG_REGISTER     = 8'b00000001;

// Now we can define our sub tasks:
// The first 4 are the sub tasks for the 'ADC' module and ... 
localparam TASK_SETUP = 0;
localparam TASK_CHECK_DONE = 1;
localparam TASK_CHANGE_REG = 2;
localparam TASK_READ_VALUE = 3;
// ... the last 4 are the instructions we can send to the 'I2C' module.
localparam INST_START_TX = 0;
localparam INST_STOP_TX = 1;
localparam INST_READ_BYTE = 2;
localparam INST_WRITE_BYTE = 3;

// The plan is to implement each of our 4 ADC sub tasks using the I2C instructions we created as follows:
// +-----------------+-------+---------------------------------------------+
// |     Stage:	     | Step: |          Description:                       |
// +-----------------+-------+---------------------------------------------+
// |   TASK_SETUP    |   0	 |  Start I2C                                  |
// |   TASK_SETUP    |   1	 |  Send Byte {address, w}                     |
// |   TASK_SETUP    |   2	 |  Send Byte to select config register        |
// |   TASK_SETUP    |   3	 |  Send Byte with config's upper byte         |
// |   TASK_SETUP    |   4	 |  Send Byte with config's lower byte         |
// |   TASK_SETUP    |   5	 |  Stop I2C                                   |
// | TASK_CHECK_DONE |   0	 |  Delay some time                            |
// | TASK_CHECK_DONE |   1	 |  Start I2C                                  |
// | TASK_CHECK_DONE |   2	 |  Send Byte {address, r}                     |
// | TASK_CHECK_DONE |   3	 |  Read Byte                                  |
// | TASK_CHECK_DONE |   4	 |  Store 1st read byte, Read Byte             |
// | TASK_CHECK_DONE |   5	 |  Stop I2C                                   |
// | TASK_CHANGE_REG |   0	 |  Verify conversion is ready                 |
// | TASK_CHANGE_REG |   1	 |  Start I2C                                  |
// | TASK_CHANGE_REG |   2	 |  Send Byte {address, w}                     |
// | TASK_CHANGE_REG |   3	 |  Send Byte to change to conversion register |
// | TASK_CHANGE_REG |   4	 |  Stop I2C                                   |
// | TASK_READ_VALUE |   0	 |  Start I2C                                  |
// | TASK_READ_VALUE |   1	 |  Send Byte {address, r}                     |
// | TASK_READ_VALUE |   2	 |  Read Byte                                  |
// | TASK_READ_VALUE |   3	 |  Store 1st read byte, Read Byte             |
// | TASK_READ_VALUE |   4	 |  Store 2nd read byte                        |
// | TASK_READ_VALUE |   5	 |  Stop I2C                                   |
// +-----------------+-------+---------------------------------------------+
//
// The way we will do this is like in a sequential processor. When a conversion is requested we will start processing each of these in order, each time performing an action and incrementing the task counter through these stages and steps.
localparam STATE_IDLE = 0;
localparam STATE_RUN_TASK = 1;
localparam STATE_WAIT_FOR_I2C = 2;
localparam STATE_INC_SUB_TASK = 3;
localparam STATE_DONE = 4;
localparam STATE_DELAY = 5;

// 'IDLE' and 'DONE' states are like we saw in the I2C module, one is the default idle state and the other is to send the done flag up to the top module.
// Our core flow will be:
// 1. Run task step by running an I2C instruction
// 2. Wait for I2C to say the instruction is done
// 3. Increment task counter to move to next task
// 4. The final delay state is for waiting between starting a conversion and for the result to be ready.

// Our state machine will need the following registers:
reg [1:0] taskIndex = 0;  // will hold (Stage) where we are in our process table above
reg [2:0] subTaskIndex = 0; // will hold (Step) where we are in our process table above
reg [4:0] state = STATE_IDLE; // is the current state in our state machine
reg [7:0] counter = 0; // will be used in the delay
reg processStarted = 0; // flag bit will be used when waiting for the I2C instruction to finish.

// < The ADC State Machine >
//
// We basically have two state machines in one here, we have the macro state machine or the outer one which handles our core loop and we have a micro state machine which will be going through all the tasks and subtasks from our table required
// to perform a full conversion.
// 
// To start we can create the outer state machine:
always_ff @(posedge clk) begin 
  case(state) 
    STATE_IDLE: begin // The first state here is the idle state:
      if(enable) begin // We wait for the 'enable' signal from top, which reset all our registers and advances us to the state with our internal state machine.
        taskIndex <= 0;
        subTaskIndex <= 0;
        dataReady <= 0;
        counter <= 0;
        state <= STATE_RUN_TASK;
      end
    end
    STATE_RUN_TASK: begin // The run task is a bit long as it holds our complete internal state machine but I will add the whole thing so as not to confuse which states are part of the outer and which are part of the inner state machine:
      case({taskIndex, subTaskIndex})
        // This covers the cases - 'Start I2C' part of every task.
        {TASK_SETUP,3'd0},
        {TASK_CHECK_DONE,3'd1},
        {TASK_CHANGE_REG,3'd1},
        {TASK_READ_VALUE,3'd0}: begin 
          instructionI2C <= INST_START_TX;
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This covers the cases - 'Send I2C byte' for the I2C SLAVE ADDRESS part of the related task
        {TASK_SETUP,3'd1},
        {TASK_CHANGE_REG,3'd2},
        {TASK_CHECK_DONE,3'd2},
        {TASK_READ_VALUE,3'd1}: begin 
          instructionI2C <= INST_WRITE_BYTE;
          byteToSendI2C <= {
            address,
            (taskIndex == TASK_CHECK_DONE || taskIndex == TASK_READ_VALUE) // This will determine if a R/W bit needs to be set
          };
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This covers the cases - 'Stop I2C' part of every task
        {TASK_SETUP, 3'd5},
        {TASK_CHECK_DONE,3'd5},
        {TASK_CHANGE_REG,3'd4},
        {TASK_READ_VALUE,3'd5}: begin 
          instructionI2C <= INST_STOP_TX;
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This covers the cases - 'Send I2C byte' for the I2C REGISTER ADDRESS part of the related tasks
        {TASK_SETUP,3'd2},
        {TASK_CHANGE_REG,3'd3}: begin 
          instructionI2C <= INST_WRITE_BYTE;
          byteToSendI2C <= (taskIndex == TASK_SETUP)? CONFIG_REGISTER : CONVERSION_REGISTER;
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This covers the cases - 'Send I2C byte' for the I2C DATA BYTE #1 (MSB) part of the related tasks
        {TASK_SETUP,3'd3}: begin 
          instructionI2C <= INST_WRITE_BYTE;
          byteToSendI2C <= {
            setupRegister[15] ? 1'b1 : 1'b0,
            1'b1, channel, 
            setupRegister[11:8]
          };
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This covers the cases - 'Send I2C byte' for the I2C DATA BYTE #2 (LSB) part of the related tasks
        {TASK_SETUP,3'd4}: begin 
          instructionI2C <= INST_WRITE_BYTE;
          byteToSendI2C <= setupRegister[7:0];
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This is just some delay issuing
        {TASK_CHECK_DONE,3'd0}: begin
          state <= STATE_DELAY;
        end
        // This covers the cases - 'Receive I2C byte' for the I2C DATA BYTE #1 (MSB) part of the related tasks
        {TASK_CHECK_DONE, 3'd3},
        {TASK_READ_VALUE, 3'd2}: begin 
          instructionI2C <= INST_READ_BYTE;
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This covers the cases - 'Receive I2C byte' for the I2C DATA BYTE #2 (LSB) and STORE the (previous) I2C DATA BYTE #1,  part of the related tasks
        {TASK_CHECK_DONE, 3'd4},
        {TASK_READ_VALUE, 3'd3}: begin 
          instructionI2C <= INST_READ_BYTE;
          outputData[15:8] <= byteReceivedI2C;
          enableI2C <= 1;
          state <= STATE_WAIT_FOR_I2C;
        end
        // This covers the cases - 'Receive I2C byte' for STORE the (previous) I2C DATA BYTE #2,  part of the related tasks
        {TASK_READ_VALUE, 3'd4}: begin 
          outputData[7:0] <= byteReceivedI2C;
          state <= STATE_INC_SUB_TASK;
        end
        {TASK_CHANGE_REG,3'd0}: begin 
          if(outputData[15])
            state <= STATE_INC_SUB_TASK;
          else begin 
            subTaskIndex <= 0;
            taskIndex <= TASK_CHECK_DONE;
          end
        end
        default:
          state <= STATE_INC_SUB_TASK;
      endcase
    end
    // The next task in our macro state machine is the "wait for i2c" state:
    STATE_WAIT_FOR_I2C: begin 
      if(~processStarted && ~completeI2C)
        processStarted <= 1;
      else if(completeI2C && processStarted) begin 
        state <= STATE_INC_SUB_TASK;
        processStarted <= 0;
        enableI2C <= 0;
      end
    end
    // The next state is for incrementing where we are in our micro process:
    STATE_INC_SUB_TASK: begin  // We saw that none of our stages has more then 5 sub-steps so if the sub-task index equals 5 we can move onto the next step otherwise we just increment the sub-task index.
      state <= STATE_RUN_TASK;
      if(subTaskIndex == 3'd5) begin 
        subTaskIndex <= 0;
        if(taskIndex == TASK_READ_VALUE) begin 
          state <= STATE_DONE;
        end else
          taskIndex <= taskIndex + 1;
      end else 
        subTaskIndex <= subTaskIndex + 1;
    end
    // Next we have a state to wait a bit before checking if the conversion results are ready:
    STATE_DELAY: begin // Here, just count 256 clock cycles which at 27 Mhz is about 10 microseconds of delay
      counter <= counter + 1;
      if(counter == 8'd111111111) begin 
        state <= STATE_INC_SUB_TASK;
      end
    end
    // Finally we have the done state which just sets the data ready flag high and waits for the enable input to go low as acknowledgement:
    STATE_DONE: begin 
      dataReady <= 1; 
      if(~enable) 
        state <= STATE_IDLE;
    end
  endcase 
  // With that the ADC module is done, it's a bit long, but I think you can agree that each single sub task is very simple and by using the table containing the procedures it's easy to know what to do at each step.
end

// It may be long, but each case is pretty simple. In-order to use the I2C building block we only need to set the instruction, enable the I2C module and wait for it to be done, we can also optionally set 'byteToSendI2C' if we are writing a byte.
// So you can see for example, there are 4 steps that we are supposed to send a start i2c instruction and the code looks like the following:
//
// {TASK_SETUP,3'd0},
// {TASK_CHECK_DONE,3'd1},
// {TASK_CHANGE_REG,3'd1},
// {TASK_READ_VALUE,3'd0}: begin
//     instructionI2C <= INST_START_TX;
//     enableI2C <= 1;
//     state <= STATE_WAIT_FOR_I2C;
// end
//
// I won't go through all these tasks, but taking a look at the table above explains what each one is doing, and they are all in the same format as the above start task.
//
// Now this article is running a bit long, but I think it is worth us taking one last detour to create a testbench before we wrap up with a final test case.

endmodule 