// < The Implementation >
//
// To begin let's create a file called 'cpu_top.v' with the following module definition:
`default_nettype none

module cpu(
  input  wire        clk, // - input clock signal, 27MHz
  input  wire        reset, // - reset signal, active high
  input  wire        btn, // - push button input, active high 
  // next we have the 4 ports required to control the flash module.
  output reg  [10:0] flashReadAddr = 0, // - 1. to interface with the flash module, we need to set the address we want to read in flashReadAddr,
  input  wire  [7:0] flashByteRead,   // - 4.  we can then take the value from flashByteRead.
  output reg         enableFlash = 0, // - 2. then set enableFlash high to start the read process. 
  input  wire        flashDataReady, // - 3. We then need to wait for flashDataReady to go high signifying that the byte was read,
  // Next we have an output register to control the on-board LEDs,
  output reg   [5:0] leds = 6'b111111, // - we initialise this register to all ones, since our LEDs are active low, so this will turn them all off by default.
  // Next we have 3 ports for writing characters to the screen. The way this will:
  output reg   [7:0] cpuChar = 0, // 1. -  this will work is we will put an ascii character into 'cpuChar'
  output reg   [5:0] cpuCharIndex = 0, // 2. - we will put the character index on screen into 'cpuCharIndex'
  output reg         writeScreen = 0  // 3. - We will then set 'writeScreen' high to trigger the value to be stored in screen memory to be displayed.
);

// We will have a 64-byte register where we will store 64 character values, and these values will be mapped to each of the screen character indices. So for example if we set character index 0 to 'A' that
// means the first character (top left) should be an 'A' and so on.
// Finally we have two ports for buttons, the reset button will restart the processor, rerunning the code from line zero, and the second button called btn is a general purpose button used with the CLR BTN 
// command to be included in assembly programs.
// Next we can add some localparam definitions:
localparam CMD_CLR = 0;
localparam CMD_ADD = 1;
localparam CMD_STA = 2; 
localparam CMD_INV = 3; 
localparam CMD_PRNT = 4; 
localparam CMD_JMPZ = 5; 
localparam CMD_WAIT = 6;
localparam CMD_HLT = 7;

// This defines the command number for each of our 8 commands. Like we spoke about in the ISA section, we will have 3 bits which will determine which of the 8 instructions is chosen. Those 3 bits will 
// represent one of these 8 'localparam' definitions.
// Next we will need some registers:
reg    [5:0] state = 0;  //  register, for the CPUs state machine, this is the state machine which implements the execution pipeline we talked about
reg   [10:0] pc = 0; //  register for the program counter which stores which line we are currently on in the code / memory, we start from address 0 of the flash memory.
reg    [7:0] a = 0, b = 0, c = 0, ac = 0; // we have the four main registers used in our ISA: A, B, C and AC each of which are 8-bits long.
reg    [7:0] param = 0, command = 0; // two registers, one which stores the current command and one which stores the current parameter. So for example if our command is 'ADD C' then this would be stored in
// the 'command' register and the value of the 'c' register would be stored in 'param', and if the current instruction has a constant parameter then the constant parameter will be stored in 'param' instead.

reg   [15:0] waitCounter = 0; // Finally we have a register for the WAIT command. This command needs to wait x milliseconds, at 27Mhz, each millisecond is 27,000 clock cycles, so we have a 16-bit register
// to count 27,000 clock cycles to know we have waited 1 millisecond.

// Next let's define the states in our cpu's state machine:
localparam STATE_FETCH = 0;
localparam STATE_FETCH_WAIT_START = 1;
localparam STATE_FETCH_WAIT_DONE = 2;
localparam STATE_DECODE = 3;
localparam STATE_RETRIEVE = 4;
localparam STATE_RETRIEVE_WAIT_START = 5;
localparam STATE_RETRIEVE_WAIT_DONE = 6;
localparam STATE_EXECUTE = 7; 
localparam STATE_HALT = 8;
localparam STATE_WAIT = 9; 
localparam STATE_PRINT = 10; 

// We have states for our 4 pipeline stages: fetch, decode, retrieve and execute. Commands that interface with the flash memory like fetch and retrieve have 3 states, one to initialize the read operation, 
// one to wait for the flash read operation to start and one to save the result once the operation is complete. The reason this is done in 3 steps instead of just 1 or 2 for example is to sort of debounce 
// the flags. If we immediately check if the 'dataReady' flag is high, we may accidentally read the previous read operation's 'dataReady' flag and think our data is ready. By first waiting for the data ready 
// flag to go low, and only then to check if it goes high we ensure that is it high from our current operation.
// Besides for these states we have a special state for HALT which basically just stops the CPU from running once the HLT instruction was executed. Finally we have special states for waiting x milliseconds
// as-well as printing to the screen as these operations take more then a single clock cycle.


// < Implementing the State Machine >
//
// To begin with, our main always block should take care of the reset condition. If the reset button is pressed it should override everything else and reset all variables to their initial values:
always_ff @(posedge clk) begin
  if(reset) begin 
    pc <= 0;
    a  <= 0;
    b  <= 0;
    c  <= 0;
    ac <= 0;
    command <= 0;
    param <= 0;
    enableFlash <= 0;
    leds <= 6'b111111;
    state <= STATE_FETCH;
  end else begin  // We make reset take precedence over our state machine by putting the entire state machine in the else section.
    case (state)
      // These three states interface with the flash module in-order to read the byte.
      // - The first state sets the enableFlash pin high, it sets the desired address to the program counter and then we move onto the state where we wait for the read operation to start.
      STATE_FETCH: begin // Our first state is the "Fetch" operation where we need to load the byte in memory at the address stored in our program counter register:
        if(~enableFlash) begin 
          flashReadAddr <= pc;
          enableFlash <= 1;
          state <= STATE_FETCH_WAIT_START;
        end
      end
      // - In the second state we simply wait for the ready flag to go low, again this is to make sure we don't accidently read the flag's status from the previous operation by mistake.
      STATE_FETCH_WAIT_START: begin 
        if(~flashDataReady) begin 
          state <= STATE_FETCH_WAIT_DONE;
        end 
      end
      // - The third state (final stage) waits for the data ready flag to go back high, where we can then store the byte read in command and we disable the flash until we need it again so that it can go back to its idle state.
      STATE_FETCH_WAIT_DONE: begin 
        if(flashDataReady) begin 
          command <= flashByteRead; 
          enableFlash <= 0;
          state <= STATE_DECODE;
        end 
      end
      // - The next pipeline stage is the decode stage where we first off increment the program counter since we just read the current byte. We then check whether the current command has a constant parameter (which requires
      // reading an extra byte from the flash memory) or whether the parameter is one of our 4 main registers.
      STATE_DECODE: begin 
        pc <= pc + 1;
        if(command[7]) begin // command has constant param - If you remember from our ISA, we set the 8th-bit (bit index 7) high if the current instruction requires loading a constant parameter so it is easy to check ...
          state <= STATE_RETRIEVE; // ... in this case we will go to the retrieve stage.
        end else begin  // In the event this command doesn't have a constant parameter ...
          param <= command[3] ? a : command[2] ? b : command[1] ? c : ac; // ...  we store one of the other registers into param based on which of the 4 bits in the instruction are set.  So ADD A will have bit index 3 set ... 
          state <= STATE_EXECUTE; // ... whereas ADD B will have bit index 2 set. Not all commands have parameters, like HLT, or some commands have other parameters like STA LED where the parameter is the led register.
        end                       // But it doesn't hurt to store one of the 4 registers into param so it is easier to just do it always instead of only doing it when required.
      end
      // The next 3 states are for the retrieve stage. These are almost identical to the fetch instructions except for what they do when the byte has been read:
      // - The first two states are exactly the same as in the fetch stage, we could have combined them if we had another register to store where to go next, ...
      STATE_RETRIEVE: begin 
        if(~enableFlash) begin 
          flashReadAddr <= pc; 
          enableFlash <= 1;
          state <= STATE_RETRIEVE_WAIT_START;
        end
      end
      // ...  but I decided to duplicate them as I feel it is a little simpler to understand.
      STATE_RETRIEVE_WAIT_START: begin 
        if(~flashDataReady) begin 
          state <= STATE_RETRIEVE_WAIT_DONE;
        end
      end
      // - In this state we store the byte read into param and go to the execute stage. We also increment the program counter again, since we read another byte and have to advance to the next byte address to receive the next instruction for next time.
      STATE_RETRIEVE_WAIT_DONE: begin 
        if(flashDataReady) begin 
          param <= flashByteRead;
          enableFlash <= 0;
          pc <= pc + 1;
          state <= STATE_EXECUTE;
        end
      end
      // - The next state is where most of the heavy lifting goes, in the execute stage we actually perform the desired instruction so let's start with the outline and then we will add each command in:
      STATE_EXECUTE: begin 
        state <= STATE_FETCH;
        // In this state we have another case statement where we check the 3 bits which define which instruction we have currently loaded. In this case statement we use our 8 command localparam definitions we defined above.
        case(command[6:4])
          // The first command we will implement is CLR:
          CMD_CLR: begin // Here we are clearing registers so the param doesn't really help us, we go over the 4 (LSb) bits which choose which variation we are working on and perform the corresponding action.
            if(command[0]) // Most of the variations simply set a register to zero, except for CLR BTN which only clears 'ac' if the user button is currently pressed otherwise it keeps the current value of 'ac'.
              ac <= 0;
            else if(command[1])
              ac <= btn ? 0 : (ac ? 1 : 0);
            else if(command[2])
              b <= 0;
            else if(command[3])
              a <= 0;
          end
          // The next command we will implement is ADD this command is a lot simpler as the value is always stored in 'ac' and the parameter is already stored in param even in the event of a constant parameter thanks to the retrieve stage.
          CMD_ADD: begin 
            ac <= ac + param;
          end
          // Next we have STA which stores the 'ac' register into a destination register based on the variation:
          CMD_STA: begin    
            if(command[0]) // Most of the 4 variations are simply storing the ac register into a different register, again since the value in each of the operations is ac it wouldn't really help us storing it in param so we need to handle each of the 4 variations here. 
              leds <= ~ac[5:0]; // The first variation inverts the value and only takes the bottom 6 bits since again the LEDs are active low and we only have 6 of them.
            else if(command[1]) 
              c <= ac;
            else if(command[2])
              b <= ac; 
            else if(command[3])
              a <= ac;
          end
          // The next instruction is the INV instruction, which simply inverts the bits of one of the registers:
          CMD_INV: begin 
            if(command[0]) // Nothing special to explain here, each variation is handled like before, and each simply flips a register's bits.
              ac <= ~ac;
            else if(command[1])
              c <= ~c;
            else if(command[2])
              b <= ~b;
            else if(command[3])
              a <= ~a;
          end
          // The next command is the PRNT instruction, which updates the character memory which is mapped to the screen.
          CMD_PRNT: begin 
            cpuCharIndex <= ac[5:0]; // We set the screen character index to the bottom 6 bits of 'ac' (only the bottom 6 since there is only 64 positions) ...
            cpuChar <= param; // ... and the actual ascii character value is stored in 'param'. 
            writeScreen <= 1; // We then set writeScreen to 1 in-order to trigger the screen memory update and ...
            state <= STATE_PRINT; // ... we go to the STATE_PRINT state to get an extra clock cycle for this instruction to give the screen memory time to write the changes.
          end
          // The next command is JMPZ which jumps to a different line in code if the ac register currently equals 0.
          CMD_JMPZ: begin 
            pc <= (ac == 8'd0) ? {3'b0, param} : pc; // The address where we want to jump to is already stored in param so here we simply check if ac equals zero, in which case we set the current value of pc to the address we want to go to.
                                                     // Otherwise we keep the current value of pc effectively doing nothing.
                                                     // It is worth noting, our program counter is 11-bits long and our parameters are only 8-bits long, meaning that even though are programs can theoretically be 2048 lines long (as our program 
                                                     // counter will go up to this value before rolling back to zero), our jump instruction can only jump to an address up to line 256. This is a limitation of our ISA which we will have to work 
                                                     // around when designing our programs.
          end
          // The next instruction we need to implement is the WAIT instruction where we wait x milliseconds, where x is the value stored in param
          CMD_WAIT: begin
            waitCounter <= 0;
            state <= STATE_WAIT; // Here we don't really do anything we just jump to the STATE_WAIT state where we will do the waiting before running the next command.
          end
          // The final instruction is the HLT instruction which simply stops execution:
          CMD_HLT: begin  
            state <= STATE_HALT; // Here also we just jump to a special state where we will just do nothing as we have finished the program.
          end
        endcase
        // This finished the internal case statement and implements all the instructions in our ISA. We can now return to implementing the final states in our outer case statement which are these special states we added for certain instructions.
      end
      // - The first was the STATE_PRINT state where we just wanted an extra clock cycle to give time for the screen memory to update. So in this state we don't do anything we just go back to our standard pipeline:
      STATE_PRINT: begin 
        writeScreen <= 0;
        state <= STATE_FETCH;
      end
      // - Next we have the state for waiting x milliseconds:
      STATE_WAIT: begin 
        if(waitCounter == 27000) begin // We count up 27,000 clock cycles which equals 1 milliseconds and ...
          param <= param - 1; // ... then decrement 'param'. So if param was 20 we will do this 20 times, essentially waiting 20 milliseconds and then when param is 0 we go back to our regular pipeline.
          waitCounter <= 0;
          if(param == 0)
            state <= STATE_FETCH;
        end else 
          waitCounter <= waitCounter + 1;
      end
      // - Finally we have the STATE_HALT state where we don't actually want to do anything, we could have left this off even but I like to include it to stress that we are doing nothing here.
      STATE_HALT: begin 
        // Just Halt here - 
      end
    endcase 
  end
end
// With that our cpu module is complete and should now be able to run programs written with out instruction set.

endmodule 