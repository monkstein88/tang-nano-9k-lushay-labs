// Tang Nano 9K: Sharing Resources
//
// Some projects require having multiple modules use a common resource. This could be for a number of reasons like the common device might be an external peripheral (e.g. sensor / storage device) 
// or it may be an expensive module so it might be to save on internal resources. Whatever the reason for doing this, special care needs to be taken when sharing resources to make sure the different
// modules don't interfere with each other.
//
// In this article we will be taking a look at multiple sharing methods, when to use them and a how you can implement them.
//
//
// < The Problem >
// 
// Before we take a look at solutions it's important to understand what problem we are trying to solve. Think of an example with two modules that need to write / read data from the external flash IC.
//
//    +----------+                                                                   
//    | Module A |                                                                
//    |          |                                           
//    |     Addr |--                                                         
//    |     Data |--                     +--------------+      +--------------+                          
//    |      R/W |--                     | Flash Module |      |   Flash IC   |                                                       
//    +----------+                       |              |      |              |                                                             
//                         ???           |         MISO |------| MISO         |                                           
//    +----------+                    ---| Addr    MOSI |------| MOSI         |                                 
//    | Module B |                    ---| Data     CLK |------| CLK          |                                             
//    |          |                    ---| R/W       CS |------| CS           |                                                  
//    |     Addr |--                     +--------------+      +--------------+                                                 
//    |     Data |--                                                                 
//    |      R/W |--                                                                   
//    +----------+                                                                         
//
// Simply OR-ing the connections from the two modules together will result in the flash module receiving a 1 if any of the modules send a high signal. So if module A would send address 10101 and 
// module B would send 01010 at the same time the flash module would receive 11111 essentially corrupting the communication. This electrical interference would result in neither of the modules being
// able to perform correctly.
//
// Now in this case we can't simply duplicate the flash module since externally we only have a single flash IC, but even internally there are times where it would be too expensive to duplicate 
// (in terms of internal registers and LUTs) and to fit your design you need to have multiple modules reuse a component.
//
// To make the above example work we need a way to wire the two modules up so that at most only 1 is using the flash module at a time.
//
// 
// < Some Options >
// 
// Choosing a solution depends on the specific requirements of the system you are building, some solutions are more lightweight while others are more robust. We can divide the multiple options into 
// two main groups, federated access and unfederated access. Basically whether or not we need a separate module to control the flow or not.
//
//
// < Unfederated Access >
// 
// In cases where the access is basic / predictable or cases where you only have two modules sharing a resource you can get away with wiring them up (effectively OR-ing the signals together) and you rely
// on a simple mechanism to make sure both devices don't use the device at the same time.
//
// One way to do this is by using time (or a counter) and dividing up the time in advance between them. For example you can say each module gets 800 clock cycles and they can each have a counter to keep
// track of when it is their turn to use the device, idling during the other module's turn.
// 
// Something to look out for though is that you need to make sure the other module finished their current transaction before starting, so if it isn't exactly aligned you may need to add a buffer between
// modules to make sure there is no overlap. For example if a module's procedure takes 12 clock cycles, then you should have a buffer at the end of that module's turn of 11 clock cycles where they can't 
// request but if they are in the middle of an operation they can finish.
//
// CLOCK CYCLES:   400       16      600        16     400      16      600       16 
//             +-----------+---+--------------+---+-----------+---+--------------+---+
//             | Module A  |   |   Module B   |   | Module A  |   |   Module B   |   | 
//             |           |   |              |   |           |   |              |   | 
//             +-----------+---+--------------+---+-----------+---+--------------+---+
//                        buffer             buffer           buffer            buffer
//
// This is a good solution when you need constant access from multiple devices, but what about a situation where we have one system always using the device and another only sometimes requires the device. 
// For example if we are building a game, we may have one module which loads in a new level, and another module which runs every frame to pull data for rendering.
//
// Loading level data is a large operation but it only happens once in a while (e.g. when you finish a level). Dividing the clock time between them would result in wasting a lot of time. If you gave it a 
// large / equal share of the time it means most clock cycles would go unused, and if you gave it a very little share to minimize this effect, then when it does have to load a level it would take a long 
// time being a heavy operation.
//
// A better solution for this kind of situation is to have one module have priority over the other. The way this works is the level loader would act as the master device and would decide when it needs the 
// shared resource or when it can be used by the other module.
//
// You can accomplish this by the level loader having an extra wire to signify it wants to use the shared resource. When the wire goes high the secondary device would idle and wait before sending any other
// commands to the shared resource. Here too the master device might need to wait a few extra clock cycles to make sure if the secondary module was in the middle of a command that it finishes.
//
// Now whenever loading a new level the level loader would gain full control of the memory making loading faster, and the rest of the time the rendering code would have full control not wasting extra time 
// on the level loader.
//
// This solution provides good performance but it only works if you have two devices, sharing with 3 or more devices using this signaling method requires more advanced handling which we will cover under 
// federated access.
//
// I brought these to examples as a way to illustrate that each use-case might be different and based on the specifics there might be a variation that works better. The main take away is you can get away 
// with not adding a new module to handle access if you have some built in method for making sure they don't use the resource at the same time. This can be done with time slicing, signaling or things like 
// that.
//
//
// < Federated Access >
//
// For more complex situations, like if the time each module will access the shared resource is less predictable or you have many modules sharing the resource, the best option is to have a standalone 
// module to manage the resource sharing.
//
// This kind of module has a few different names like an arbiter / controller / scheduler but the main idea is to implement a system where modules can request to use a shared resource and it is up to the 
// controller to accept these requests and decide who is currently granted the resource using some kind of logic.
//
// A basic example of this is a queuing system or a first in first out approach. In this approach the controller implements a queue and every module that wants to use the shared resource gets added to the
// queue. Then based on the order of the queue one module at a time will be granted the resource, once done they are removed from the queue and the next in line gets their turn.
//
// This can be made more complex with prioritization logic, where certain modules will be put into a higher priority queue which is processed first. You may also want to add logic for when a module is
// allowed to request access, for example you may not allow a prioritised module to ask twice in a row allowing for other resources to also get scheduled.
//
// And also you can control if each time a module is given access if it is limited to a single command or if they can hold the access for multiple commands. Allowing for multiple commands allows you to 
// create semaphores which is required for handling critical sections that require atomic operations (or mutually exclusive operations).
//
// An example of this could be you have a system where two modules increment the same memory address. For instance if you are building a router with 2 ethernet ports and you have a module for each port 
// and you want to store the total bandwidth over both.
//
// The problem with incrementing from memory is that it is essentially 2 operations, you need to read the current value and then rewrite the new value with the addition. If your controller doesn't allow 
// 1 module to complete both of these steps in a single go, the value in memory can get trampled losing data. If for example the current total bandwidth is 12MB and each of the two port modules wants to
// add 1MB, if the controller schedules it as follows:
//
// 1. Read current total Module A (value 12)
// 2. Read current total Module B (value 12)
// 3. Write new total Module A (value 13)
// 4. Write new total Module B (value 13)
//
// The both modules will receive 12MB as the current value and then both will write 13MB back (when the real value is 14MB). This ordering isn't that far fetched also, with a queue system, module B could 
// already be in the queue before module A is able to finish their first operation and requests again.
//
// In the above example you would need a controller which allows A to not release control of the shared memory until after both reading and writing the new value making the increment operation atomic.
//
// With all that being said I think we can get into some implementation. In this article we will be creating a controller for federated memory access so that three modules can share the same memory.
//
// This holds the clock and all wires for the screen. Next we can create a file called top.v with the following:
module top
#(
  /* Tang Nano 9K Board - featuring GOWIN FPGA: GW1NR-LV9 QFN88P (rev.C) */
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT_MS = 10 // make startup delay of 10 [ms]
)
(
  input wire EXT_CLK,  // This is the external clock source on the board - expected 27 [MHz] oscillator. 
  input wire BTN_S1, // This pin is tied to a button 'S1' on the board, and will be used as a 'reset' source (active-low) 
  input wire BTN_S2, // This pin is tied to a button 'S2' on the board, and will be used as a general user input source (active-low) 
  output reg [5:0] LED_O=6'b1, // 6 Orange LEDs on the board, active-low , default to all high (leds are OFF)
  // LCD 0.96" SPI interface - SSD1306 controller
  output wire LCD_RST, // reset: active-low   
  output wire LCD_SPI_CS, // chip-select: active-low Note: multiple bytes can be sent without needing to change the chip select each time.
  output wire LCD_SPI_SCLK, // spi clock signal: idle-low 
  output wire LCD_SPI_DIN, // data input. Note: data is latched on the rising edge of the clock and is updated on the falling edge. MSb is sent first.
  output wire LCD_DC,  // data/command select: active-low - data, active-high - command

  input  wire UART_RX,  // UART|RX pin - 8N1 config
  output wire UART_TX,  // UART|TX pin - 8N1 config
  
  output wire FLASH_SPI_CS,  // chip select for flash memory
  output wire FLASH_SPI_MOSI, // master out slave in for flash memory
  input  wire FLASH_SPI_MISO, // master in slave out for flash memory
  output wire FLASH_SPI_CLK  //  clock signal for flash memory
);
localparam STARTUP_WAIT_CYCL = ((EXT_CLK_FREQ/1000)*STARTUP_WAIT_MS);

wire enabled, readWrite;
wire [31:0] dataToMem, dataFromMem; 
wire [7:0] address; 

wire req1, req2, req3;
wire [2:0] grantedAccess; 
wire readWrite1, readWrite2, readWrite3;
wire [31:0] currentMemVal, dataToMem2, dataToMem3; 
wire [7:0] address1, address2, address3;

wire [9:0] pixelAddress; 
wire [7:0] textPixelData; 
wire [5:0] charAddress;
reg  [7:0] charOutput; 

// the screen iterates over all pixels on screen in 1024 bytes. Each time it requests a single byte using the pixelAddress register ...
screen #(STARTUP_WAIT_CYCL) scr ( // Hook up our screen module.
 .clk(EXT_CLK),
 .ioReset(LCD_RST),
 .ioCs(LCD_SPI_CS),
 .ioSclk(LCD_SPI_SCLK),
 .ioSdin(LCD_SPI_DIN),
 .ioDc(LCD_DC),
 .pixelAddress(pixelAddress),
 .pixelData(textPixelData)
);
// ... The text engine takes this pixel address and converts it into a character index by splitting the screens pixels into 4 rows of 16 characters...
textEngine te(
  .clk(EXT_CLK),
  .pixelAddress(pixelAddress),
  .pixelData(textPixelData),
  .charAddress(charAddress),
  .charOutput(charOutput)
);

memController fc(
  .clk(EXT_CLK),
  .requestingMemory({req3, req2, req1}),
  .grantedAccess(grantedAccess),
  .enabled(enabled),
  .address(address),
  .dataToMem(dataToMem),
  .readWrite(readWrite),
  .addr1(address1),
  .addr2(address2),
  .addr3(address3),
  .dataToMem1(0),
  .dataToMem2(dataToMem2),
  .dataToMem3(dataToMem3),
  .readWrite1(readWrite1),
  .readWrite2(readWrite2),
  .readWrite3(readWrite3)
);

sharedMemory sm(
  .clk(EXT_CLK),
  .address(address),
  .readWrite(readWrite),
  .dataOut(dataFromMem),
  .dataIn(dataToMem),
  .enabled(enabled)
);

// This might look like a lot but it is just because we are connecting a number of components here. The ports our module receive are simply the wires to 
// drive the screen and the main clock signal. The first group of wires/registers are for driving the shared memory. The next group is all the wires for
// the controller, and the final group of wires and registers is for the screen and text engine.
// After that we simply add instances for our screen driver, text engine, controller and shared memory.
// 
// Next we can create instances of our memory read / memory inc modules:
memoryRead mr(
  .clk(EXT_CLK),
  .grantedAccess(grantedAccess[0]),
  .requestingMemory(req1),
  .address(address1),
  .readWrite(readWrite1),
  .inputData(dataFromMem),
  .outputData(currentMemVal)
);

memoryIncAtomic m1(
  .clk(EXT_CLK),
  .grantedAccess(grantedAccess[1]),
  .requestingMemory(req2),
  .address(address2),
  .readWrite(readWrite2),
  .inputData(dataFromMem),
  .outputData(dataToMem2)
);

memoryIncAtomic m2(
  .clk(EXT_CLK),
  .grantedAccess(grantedAccess[2]),
  .requestingMemory(req3),
  .address(address3),
  .readWrite(readWrite3),
  .inputData(dataFromMem),
  .outputData(dataToMem3)
);
// Each one gets their own 'grantedAccess' bit and 'request' bit, and they have the other connections for the controller and from memory. At this stage we have 1 module 
// reading from memory once a second, and another two modules each incrementing the same memory once a second.

// The last step is just to display the value in memory so we can see it being incremented correctly:
wire [1:0] rowNumber;
assign rowNumber = charAddress[5:4];

genvar i;
generate 
  for(i=0; i<8; i=i+1) begin: hexVal
    wire[7:0] hexChar;
    toHex converter(EXT_CLK, currentMemVal[(i*4)+:4], hexChar);
  end 
endgenerate

always_ff @(posedge EXT_CLK) begin 
  if(rowNumber == 2'd0) begin 
    case(charAddress[3:0])
      0: charOutput <= "0";
      1: charOutput <= "x";
      2: charOutput <= hexVal[7].hexChar;
      3: charOutput <= hexVal[6].hexChar;
      4: charOutput <= hexVal[5].hexChar;
      5: charOutput <= hexVal[4].hexChar;
      6: charOutput <= hexVal[3].hexChar;
      7: charOutput <= hexVal[2].hexChar;
      8: charOutput <= hexVal[1].hexChar;
      9: charOutput <= hexVal[0].hexChar;
      default: charOutput <= " ";
    endcase
  end
end

// We create a wire to extract the row number and we generate 8 hex converters to convert the 8 hex chars needed to represent our 32-bit value. The always block will check 
// if we are on the first text row of the screen and if so output 0x followed by the 8 hex characters.
endmodule

// To make this work we also need to add our hex converter module, you can add this at the top / bottom of the same file top.v:
module toHex(
  input wire clk,
  input wire [3:0] value,
  output reg [7:0] hexChar = "0"
);

always_ff @(posedge clk) begin 
  hexChar <= (value <= 9) ? "0" + value : "A" + (value-10);
end 
endmodule


// Outcome:
// If you see it counting up by 2 every second then you know everything is working and there is no interference between our 3 modules and all of them are sharing a common memory module.

// < Conclusion >
// In this article we took a look at the problem of sharing resources and some ways to fix it, we also built a pretty robust controller to allow for resource sharing and for mutual 
// exclusion. With that being said this can be taken further by adding more logic in terms of nextInLine or having multiple priority queues to allow for things like interrupts, etc.