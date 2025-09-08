// < Tang Nano 9K: Our First CPU >
//
// This is part 10 in the tang nano series which is a sort of milestone, so we wanted to do something a bit different for this article. In this article we will be going full-circle back to the LED counter example where it all 
// started, but this time we will be implementing the project using software.
// To accomplish this there are a few things we need to implement, like an instruction set architecture, a cpu core that can process this bytecode and an assembler to convert our assembly programs into bytecode in our 
// instruction set format.
// But like usual before we get into building things, let us take a brief detour to go over some of the theory.
//
// < What is a CPU ? >
//
// CPUs can mean a lot of different things to different people, so let me start off by explaining what I am talking about. I am referring to a core (we will build in verilog) that will receive code line by line and execute 
// each instruction accordingly.
// What this gives you is a general purpose hardware design, where instead of building a specific project, you are building the building-blocks and allowing for external software to "orchestrate" the different internal 
// operations to compose them into many different use-cases.
// This is the same way all our devices, like computers, phones, etc. work, you have a processor which implements a specific instruction set architecture, things like the RISC V architecture have been rising in popularity 
// being completely open and free or the x86 architecture has been the default for computer processors.
// These processors have a very specific bit-sequence for each instruction and the processor knows how to decode this bit-sequence to understand what to do for each instruction.
// Writing code in binary is not that convenient, so typically you have something called an assembler which converts each command from a text representation into the binary representation.
// For example we may have an instruction to clear a register called "A", the processor may want to receive this instruction as 01100001, this is the bytecode for this command. Instead the programmer writing this they would
// write the assembly languages textual representation, something like "CLR A" which the assembler would take and convert into the bytecode version.
// There are even higher level abstractions that we won't get into in this article, but typically people don't write assembly programs, they use higher level languages like C or Rust which provide an abstraction layer to 
// write more concise code which then gets compiled into assembly and assembled into bytecode.
//
// < The ISA >
// 
// The ISA (or instruction set architecture) basically defines the syntax, bytecode and behaviour of the software language we are building.
// To make an instruction set where you can start to make interesting programs requires most if not all of the following:
//
// - A way to work with data (load data / basic arithmetic)
// - variables or storage for calculation (usually general purpose registers)
// - A way to get user-input
// - A way to output something for a user
// - Some kind of conditional statement (for implementing if / else type statements)
// - A way to jump from one place to another in code (which allows for loops)
//
// Now "working with data" is a very general sentence which also needs decisions like what kind of data and what operations. You may be making a more complex graphics processor where the instructions perform math operations 
// on matrices like matrix multiplication or you may have special data type operations like linked lists, etc.
// For our first processor we will be creating a simple 8-bit processor, this means our registers will be 8-bit are math operations will be 8-bit and our instructions will revolve around 8-bit parameters.
// In our processor we will have 4 general purpose registers, as a sort of convention the main register is called AC or accumulator since you generally store the result of operations in this register. The other registers 
// simply will get a letter as there name so we will have A, B and C.
//
// Next for operations we will implement:
//
// 1. Clear a register
// 2. Invert a register
// 3. Add number to a register
// 4. Add 2 registers together
//
// This will allow us to perform addition and multiplication (since multiplication can be implemented as repeated addition) and using the invert command we can implement subtraction using 2's complement and with subtraction you 
// could theoretically maybe also implement division as a repeated subtraction.
// So by implementing these 4 options we get basic arithmetic operations. It is worth mentioning that if multiplication and division were important to you, then I would add a dedicated instruction to perform them in hardware in
// a single operation as opposed to having to "implement" it in code which is a lot less performant, but for our example I will mostly be using addition.
//
// Besides these 4 commands we will also implement some other things:
//
// - Store AC into one of the other registers
// - Output character to user via Screen
// - Set LED values
// - Way to check if button is pressed as user input
// - A way to conditionally jump between lines of code
// - A command to wait x milliseconds
// - A way to stop the execution of code.
//
// This will give us a good base set of commands to create some programs. The way I decided to implement these commands are as eight instructions where each instruction can have 1 of 4 parameters types.
//
// ; CLR A/B/BTN/AC
// CLR A    ; clear a register
// CLR B    ; clear b register
// CLR BTN  ; clear ac if button is pressed
// CLR AC   ; clear ac register
//
// ; STA A/B/C/LED
// STA A    ; store ac in a register
// STA B    ; store ac in b register
// STA C    ; store ac in c register
// STA LED  ; set leds to bottom 6 bits of ac
//
// ; INV A/B/C/AC
// INV A    ; invert bits of register a
// INV B    ; invert bits of register b
// INV C    ; invert bits of register c
// INV AC   ; invert bits of register ac
//
// ; HLT
// HLT      ; halt execution (stop program)
//
// ; ADD A/B/C/Constant
// ADD A    ; ac = ac + a
// ADD B    ; ac = ac + b
// ADD C    ; ac = ac + c
// ADD 20   ; ac = ac + 20
//
// ; PRNT A/B/C/Constant (ac should have the screen char index)
// PRNT A   ; screen[ac] = a (a should be ascii value)
// PRNT B   ; screen[ac] = b (b should be ascii value)
// PRNT C   ; screen[ac] = c (c should be ascii value)
// PRNT 110 ; screen[ac] = 110
//
// ; JMPZ A/B/C/Constant 
// JMPZ A   ; go to line a in code if ac == 0
// JMPZ B   ; go to line b in code if ac == 0
// JMPZ C   ; go to line c in code if ac == 0
// JMPZ 20  ; go to line 20 in code if ac == 0
//
// ; WAIT A/B/C/Constant
// WAIT A   ; wait a milliseconds
// WAIT B   ; wait b milliseconds
// WAIT C   ; wait c milliseconds
// WAIT 100 ; wait 100 milliseconds
//
// So as you can see here we have 8 instructions where most of them have 4 variations.
//
// Next we need to decide how we will store this in memory, with 8 operations we need at least 3 bits to differentiate between them, and then for each of them we have 4 options. Since we probably won't be using less then a byte
// per instruction I propose for this project the following layout:
//                                                 
//             |   INSTRUCTION   |  |         VARIATION         |                                                                                                                   
//      +-----+------+------+-----+-----+------+------+-----+-----+                                                                                            
//      |     |      |      |     |     |      |      |     |     |                                                                                             
//      |     |      |      |     |     |      |      |     |     |                                                                                             
//      +-----+------+------+-----+-----+------+------+-----+-----+                                                                                             
//         |
//         |
//       CONSTANT  ( '1': meaning we're adding a CONSTANT, '0' meaning we're adding REGISTER)                                                                                         
//       parameter
//
//
// So for example if the first command is CLR then it's four variations would be:
//
// CLR A   ; 00001000 -> 0 000 1000
// CLR B   ; 00000100 -> 0 000 0100
// CLR BTN ; 00000010 -> 0 000 0010
// CLR AC  ; 00000001 -> 0 000 0001
//
// Next let's take a look at the next instruction ADD here we have a constant parameter so it would be represented as follows:
//
// ADD A   ; 00011000 -> 0 001 1000
// ADD B   ; 00010100 -> 0 001 0100
// ADD C   ; 00010010 -> 0 001 0010
// ADD 20  ; 10010001 -> 1 001 0001
//
// The first 3 are exactly like the CLR command, the last option since it is using a constant parameter we also set the 1st bit high.
//
// Since each of the 4 variations have there own bit and only 1-bit is ever on, and also since the commands with constant parameters have there own bit, we can very easily decode these options by simply checking a single bit.
// It is worth noting that we didn't actually store the constant value, in the example above we just stored a byte represented the instruction "add constant" but we will need to store another byte in memory with the actual value. 
// This is why we distinguish these commands with the extra flag bit so we will know when we need to load another byte with the value and when not.
// Now don't worry if some of this feels random, if this is your first CPU design the decisions I took above of which instructions to implement and how to represent them may seem arbitrary, and the truth is they are basically 
// arbitrary.
// 
// You have full control over what and how to implement the architecture, and by building and using your architecture it will give you ideas on improvements or changes that you can make in future designs. So these are arbitrary
// decisions based on previous instruction sets I have worked with, in an attempt to go for the simplest / minimal instruction set, that would still be usable and would provide an example of the concepts and a starting point for
// your future explorations in ISA.
// Besides experimenting, another good way to learn more is by exploring other ISAs. Our instruction set only has about 8 instructions but x86 on the other hand has (depending on how you count) closer to 1000, so there are alot of 
// other things that can be added. Try to look at instruction sets that perform things similar to what you are trying to do.
// For example you can look at old processor instruction sets like the 8085, or you may want to look at the avr instruction set used by arduinos as examples of mcu type instruction sets. Like mentioned above there is the risc series 
// of instruction sets and the x86 instruction set which is what your computer is probably using.
// There are even "educational" instruction sets developed for learning purposes, without real processors that use them like Mano machine instruction set or MMIX.
//
// With the instruction set planned out, let us go over some implementation theory.
//
// < CPU Core >
//
// Implementing a core that can process an instruction set is usually done with a pipeline design. Not to be confused by pipelining which is parallelising the execution pipeline, I am more referring to the steps themselves required
// to execute a single command.
// In our processor we will have the following pipeline stages:
//
// - Fetch - load the next command from memory
// - Decode - process the command / prepare parameters if possible
// - Retrieve - optionally fetch another byte if constant parameter is used
// - Execute - Run the command once everything is loaded
//
// This is typically the stages in most processors of this type, although sometimes there are more stages for things like writing data back to memory we don't have in our ISA or sometimes these steps may be divided differently.
// Modern processors perform all these steps in parallel, so while line 1 is executing, line 2 is retrieving, and line 3 is decoding and line 4 is fetching. Doing this can dramatically speed up your processor as you are always 
// "executing".
// We won't be doing this as it raises more complexities, for example, let's say we jump to another line of code, then the lines currently being fetched / decoded are no longer relevant and we would need to handle that, also the
// retrieve step is optional so we would need to account for that. To keep things simple, we will only be performing one of these steps at a time.
//
// Let's go over how we will implement these stages:
//
// < The Fetch Stage > 
//
// We will have a register which stores where we are in our program, this is usually called PC or "program counter" as it is a counter that stores the line number.
// In the fetch stage we will request the byte in memory at the address pointed to by the PC register, this byte that we will receive is the command byte in our bytecode format.
//
// < The Decode Stage >
//
// Here we will take the byte we read and do a little processing on it. We will check whether or not we need to go to the retrieve stage, this is based on whether or not the bit for the "has constant parameter" is high.
// In the event the parameter is not in the next byte then we can also prepare the parameter already based on the variation.
//
// < The Retrieve Stage >
// 
// If the parameter was a constant, requiring us to read another byte from memory with its value, then in this stage we will request the next byte from memory and store the value as the parameter for the current instruction.
//
// < The Execute Stage >
// 
// This is the where we have everything we need, and here we actually perform the desired operation. For each instruction it is a bit different, but for example if we are currently executing the instruction ADD B then here we 
// would do: ac <= ac + b.
//
// By implementing these four stages we will have a processor capable of running our instruction set. With the theory done, let's get into some implementation:
//
// < Some Prerequisites >
//
// Before we start implementing our cpu verilog module we will need the 'screen.v' and 'text.v' modules which we have been using along with the font file. 
// Besides these we will also need a module to read our code. We will be storing our code in the external flash, as it is easy to program, but that means we need a way to load a specific byte from flash. For this we can repurpose 
// our flash module which we created originally created - 'flash.v'
// The main change we need to make there, is it used to read a whole "page" of bytes and we only want it to read a single byte.
//
//
// < The Top Module >
//
// The next thing we need to implement is the top module which will wire up all our other modules, to start off with create a file called top.v with the following module definition:
// For ports, we have the clock signal, the 5 ports for the screen, we have another 4 ports for the external flash, two ports for the two on-board buttons and our 6 LEDs.

`default_nettype none

module top
#(
  /* Tang Nano 9K Board - featuring GOWIN FPGA: GW1NR-LV9 QFN88P (rev.C) */
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT_MS = 10 // make startup delay of 10 [ms] for our LCD screen
)
(
  input wire EXT_CLK,  // This is the external clock source on the board - expected 27 [MHz] oscillator. (on the Tang Nano 9K board)
  input wire BTN_S1, // This pin is tied to a button 'S1' on the board, and will be used as a 'reset' source (active-low), (on the Tang Nano 9K board)
  input wire BTN_S2, // This pin is tied to a button 'S2' on the board, and will be used as a general user input source (active-low), (on the Tang Nano 9K board)
  output reg [5:0] LED_O={6{1'b1}}, // 6 Orange LEDs on the board, active-low , default to all high (leds are OFF)
  // LCD 0.96" (128x64 pixels) SPI interface - SSD1306 controller
  output wire LCD_RST, // reset: active-low   
  output wire LCD_SPI_CS, // chip-select: active-low Note: multiple bytes can be sent without needing to change the chip select each time.
  output wire LCD_SPI_SCLK, // spi clock signal: idle-low 
  output wire LCD_SPI_DIN, // data input. Note: data is latched on the rising edge of the clock and is updated on the falling edge. MSb is sent first.
  output wire LCD_DC,  // data/command select: active-low - data, active-high - command

  input  wire UART_RX,  // UART|RX pin - 8N1 config (using pins of IC BL616 USB-UART bride on the Tang Nano 9K board)
  output wire UART_TX,  // UART|TX pin - 8N1 config (using pins of IC BL616 USB-UART bride on the Tang Nano 9K board)
  
  output wire FLASH_SPI_CS,  // chip select for flash memory (on the Tang Nano 9K board)
  output wire FLASH_SPI_MOSI, // master out slave in for flash memory (on the Tang Nano 9K board)
  input  wire FLASH_SPI_MISO, // master in slave out for flash memory (on the Tang Nano 9K board)
  output wire FLASH_SPI_CLK   //  clock signal for flash memory (on the Tang Nano 9K board)
);

localparam STARTUP_WAIT_CYCL = ((EXT_CLK_FREQ/1000)*STARTUP_WAIT_MS);

// Next let's create some intermediate registers for our buttons:
reg btn1Reg = 1, btn2Reg = 1;
always_ff @(negedge EXT_CLK) begin 
  btn1Reg <= BTN_S1 ? 0 : 1;
  btn2Reg <= BTN_S2 ? 0 : 1;
end
// This serves two purposes, 1 it inverts the button, the buttons are also active low, but I prefer using active high so we flip them (purely personal preference). The other thing we are doing is we are separating the button input from
// the button value. Muxing in a new 1 or 0 based on the input pin, this is useful here since the buttons are on the 1.8v bank and our other components are on the 3.3v banks so this allows the router to separate the value from the bank
// so we don't get a conflict.

// Next we have the screen and text engine - we setup setup is like in all our articles - our screen and text engine modules as follows: LCD-Screen and Text-Engine related signals:
wire [9:0] pixelAddress;  // A value from 0 - 1023 , which disects the screen into addresses of pixel bytes
wire [7:0] textPixelData; // pixel byte data - a vertical column of 8-pixel bits
wire [5:0] charAddress;   // A value from 0 - 63
reg  [7:0] charOutput = " ";    // A printable ASCII character - init <empty> char
// the screen iterates over all pixels on screen in 1024 bytes. Each time it requests a single byte using the 'pixelAddress' register ...
screenDriver #(STARTUP_WAIT_CYCL) scr ( // Hook up our screen module.
  .clk(EXT_CLK),
  .ioReset(LCD_RST),
  .ioCs(LCD_SPI_CS),
  .ioSclk(LCD_SPI_SCLK),
  .ioSdin(LCD_SPI_DIN),
  .ioDc(LCD_DC),
  .pixelAddress(pixelAddress), // -- output from 'screen'
  .pixelData(textPixelData) // -- input to 'screen'
);
// ... The text engine takes this pixel address and converts it into a character index by splitting the screens pixels into 4 rows of 16 characters...
textEngine te( // allows us set the character we want on screen for each index into 'charOutput' and it will handle drawing the character and interfacing with the OLED screen.
  .clk(EXT_CLK),
  .pixelAddress(pixelAddress), // -- input to 'text Engine'
  .pixelData(textPixelData),   // -- output from 'text Engine'
  .charAddress(charAddress),   // -- output from 'text Engine'
  .charOutput(charOutput)     // -- input to 'text Engine'
);

// After these we can instantiate our flash module:
wire [10:0] flashReadAddr;
wire  [7:0] byteRead;
wire        enableFlash;
wire        flashDataReady;

flash externalFlahs(
  .clk(EXT_CLK),      
  .flashClk(FLASH_SPI_CLK),     
  .flashMiso(FLASH_SPI_MISO),   
  .flashMosi(FLASH_SPI_MOSI),    
  .flashCs(FLASH_SPI_CS),      
  .addr(flashReadAddr),        
  .byteRead(byteRead),   
  .enable(enableFlash),   
  .dataReady(flashDataReady)
);

// Leaving the last module we need to instantiate be our cpu module:

wire [7:0] cpuChar;
wire [5:0] cpuCharIndex;
wire       writeScreen;

cpu c(
  .clk(EXT_CLK),
  .reset(btn1Reg),
  .btn(btn2Reg), 

  .flashReadAddr(flashReadAddr),
  .flashByteRead(byteRead),
  .enableFlash(enableFlash),
  .flashDataReady(flashDataReady),

  .leds(LED_O),

  .cpuChar(cpuChar),
  .cpuCharIndex(cpuCharIndex),
  .writeScreen(writeScreen) 
);

// With that we have all our modules instantiated and hooked up to each other. The last thing we need to do is our screen memory and to map it to the text engine so it will be displayed on screen.
// We already created the wires here for the character, character index and the flag wire writeScreen which tells us when to store a new character.
// To implement this screen memory we can add the following:
reg [7:0] screenBuffer [0:63] = '{default:'0}; // We start off by creating the screen buffer register, which needs to be big enough to hold 64 different  ASCII (byte) characters. 
always_ff @(posedge EXT_CLK) begin // We then have an always block where ...
  if(writeScreen)
    screenBuffer[cpuCharIndex] <= cpuChar; // ... if the writeScreen flag is set we store the value from cpuChar into the screen buffer at character index cpuCharIndex ...
  else
    charOutput <= screenBuffer[charAddress]; // ... when the writeScreen flag is not high, we instead interface with the text engine module and set the desired character to display from memory based on 
  end                                        // the charAddress which stores the character index of the current character being drawn.


endmodule


// We could technically now build and run our project, but without a software program written in our ISA it won't do much. So before building and running our cpu core let's write a program using our new ISA.