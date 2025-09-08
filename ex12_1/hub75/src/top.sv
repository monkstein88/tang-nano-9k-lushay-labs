//  < Tang Nano 9K: HUB75 LED Panels (64 (columns) x 64 (rows) pixels)>
//
// In this article, we will dive into LED pixel matrix panels and create some drivers to interface with this type of screen. The type of panel we are going to be using is sometimes called a HUB75 panel based on the interface and comes in a 
// variety of sizes and densities.
// This article was developed by Chandler Klüser and follows his exploration of this protocol.
//
// 
// < What is HUB75 ?
//
// It sounds like a simple question, and based on the popularity of these boards you would think it would be easy to find the source. However, it seems HUB75 is a protocol that has emerged from the LED panel industry without being formally 
// standardized by any specific party.
// These LED matrix panels essentially work by having a row of pixels shifted into a shift register and then a demultiplexer to select which of the rows the data should be displayed on. By altering through the rows quickly you can draw an entire 
// image to the panel.
// So essentially you select a row using the address bits, then shift in a pixel value for each pixel in the row. With the row data pushed in, you latch the data to store and output the value of the shift register to the LED of that row; repeating
// the cycle per row.
// Each pixel is an RGB pixel, meaning for each pixel you output 3 bits one for if the red LED in the pixel should be lit, one for green, and one for blue. In this article, we will be using a 64x64 LED panel, so we need to shift in 64 RGB values
// for each line.
//
// ---*     |   *---*     |   *---*     |   *---*     |   *--      ---*     |   *---*     |   *---*     |   *---*     |                    
//    |     |   |   |     |   |   |     |   |   |     |   |           |     |   |   |     |   |   |     |   |   |     |   |              
//   *-------*  |  *-------*  |  *-------*  |  *-------*  |          *-------*  |  *-------*  |  *-------*  |  *-------*  |              
//   |I     v|  |  |I     v|  |  |I     v|  |  |I     v|  |          |I     v|  |  |I     v|  |  |I     v|  |  |I     v|  |              
//   |N     C|  |  |N     C|  |  |N     C|  |  |N     C|  |          |N     C|  |  |N     C|  |  |N     C|  |  |N     C|  |              
//   |      L|  |  |      L|  |  |      L|  |  |      L|  |   ....   |      L|  |  |      L|  |  |      L|  |  |      L|  |                   
//   |O     K|  |  |O     K|  |  |O     K|  |  |O     K|  |          |O     K|  |  |O     K|  |  |O     K|  |  |O     K|  |              
//   |U      |  |  |U      |  |  |U      |  |  |U      |  |          |U      |  |  |U      |  |  |U      |  |  |U      |  |              
//   |T      |  |  |T      |  |  |T      |  |  |T      |  |          |T      |  |  |T      |  |  |T      |  |  |T      |  |              
//   *-------*  |  *-------*  |  *-------*  |  *-------*  |          *-------*  |  *-------*  |  *-------*  |  *-------*  |              
//    |         |   |         |   |         |   |         |           |         |   |         |   |         |   |         |              
//    *---------*   *---------*   *---------*   *---------*           *---------*   *---------*   *---------*   *---------*           
//
//                                                64 SHIFT REGISTERS = 64 COLUMNS   
//
// With 3 bits of color data per pixel, you essentially have 8 possible color options per update just like the ZX Spectrum. The HUB75 connector to interface this type of screen has the following pinout:
//
//          +---+---+   
//   RED0   | 1 | 16|    GREEN0
//          +---+---+   
//  BLUE0   | 2 | 15|    GND
//          +---+---+   
//   RED1   | 3 | 14|    GREEN1
//        +-+---+---+   
//  BLUE1 | | 4 | 13|    E
//        | +---+---+   
//      A | | 5 | 12|    B
//        +-+---+---+   
//      C   | 6 | 11|    D
//          +---+---+   
//    CLK   | 7 | 10|    LATCH
//          +---+---+   
//    /OE   | 8 | 9 |    GND
//          +---+---+   
//          
//      HUB75 Connector
//
// Instead of going through 32 lines, you have 2 channels of pixels RGB1 and RGB2 making each update draw two lines at a time, giving you only 32 lines to address. The addressing is done using the A, B, C, and D inputs. The way the 2 channels of 
// pixels work, is that the top half of the board is controlled by RGB1 and the bottom half of the board is updated by RGB2 so when you update the first line you also update line 17, and then line 2 and line 18, etc.
// 
//                                                              64 [columns]
//              
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//    32    |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//  [rows]  |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|     Driven by RED1, BLUE1 and GREEN1 pins
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//          |x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|x|
//         ----------------------------------------------------------------------------------------------------------------------------------
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|   Driven by RED2, BLUE2 and GREEN2 pins
//    32    |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//  [rows]  |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//          |o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|o|
//
// 
// So again you select 1 of the 32 address lines using A, B, C, D and E which will internally connect the 2 RGB channels to the correct pair.
//
//            
//                                  /----+
//                                 /     |----
//                                /      |----
//                               /       |----
//                              /        |----
//                             /         |----
//                            /          |----
//                RGB DATA   |           |----
//               ------------|    DEMUX  |----   16 PAIR OF LINES
//                           |           |----   
//                           *\          |----
//                           | \         |----
//                           | *\        |----
//                           | | \       |----
//                           | | *\      |----
//                           | | | \     |----
//                           | | | *\    |----
//                           | | | | *\--+   
//                           | | | | |
//                           A B C D E
//
//
// Other than that we have a CLK signal which is used to shift data into the shift register chain and a LATCH signal to move the shifted-in data to the output (pixels). This allows you to first shift out the entire row before updating the screen
// (which would cause flickering / scrolling).
// Finally OE or Output Enable is used as the global output switch to turn on and off all the pixels of the screen. This can also be modulated to control the brightness intensity of the output. These screens, given enough current, can be quite 
// bright so by limiting the amount of time the output is enabled (OE is usually active low) you can dial in the brightness and current consumption.
// Another feature of these boards is their ability to be daisy-chained extending the pixel count to any arbitrary size.
//                                       
// ...
// 
// So for 2 boards, you would just shift in 128 pixel values instead of 64 and everything else would stay the same making it easier to scale up.
// With that theory out of the way, we can start with electrically connecting the Tang Nano to this panel.
//
//
// < The Electronics >
//
// Luckily not too much is needed, the logic interface can be run directly via 3.3V so only some sort of connector is needed to be wired up and no other passive components are required.
// In this example, we will be wiring it up like so, but any pins (in the 3.3v banks) could work for this:
//
// ...
//
// Standard header pins can be used to create a 2x8 connector for the panel's cable again the pinout for the connector should be the following:
//
// ...
//
// The only important thing to remember is the direction of the header, these ribbon cables usually have a key or outdent which allows it to slot in, in the correct direction. This can be seen in the image above next to the BLUE1 and A pins there 
// is a slot. When creating a connector using standard male headers, you won't have a special key and you need to keep track of this manually.
// Once wired up you should have something like the following:
//
// ...
//
// This will allow you to connect up the LED panel to the TangNano directly like so:
//
// ...
//
// Other than that, the LED panel also requires hooking up the power signal to its external power pins. The voltage range is usually pretty flexible and can run even at 3.3v but ideally should be run at around 4-5v. The panel can consume a lot 
// of power if all the LEDs are lit (I was reaching 1-2 amps with PWM) so a sufficient power supply should be used.
// At lower voltages (3.3v) I also noticed more flickering artifacts on unlit (black) pixels, but other than that the voltage mostly affects the brightness of the colors.
// For the Tang Nano 9K itself, we will be powering it with the USB cable so nothing special there to setup. With the electronics done, we can now start implementing our first LED Matrix driver.
//


// < HUB75 Hello World >
// 
// As we saw, to drive the HUB75 LED panel, we need to select a row (row pair) using the address lines, shift in 64-pixel values per channel, and then latch the data to display it on the screen.
//
//                                         .                                                  .                  
//                                         .                                                  .                                                                                                                                                                                     
//         '1'        +--+  +--+  +--+  +--.  +--+  +--+  +--+                                .
//  CLK:              |  |  |  |  |  |  |  .  |  |  |  |  |  |                                .                                                                                                                                        
//         '0'  ------+  +--+  +--+  +--+  .--+  +--+  +--+  +--------------------------------.------                                                                                                             
//                                         .                                                  .                                                                                                                                                                                                                  
//         '1'  ---------------------------.-----------------------------------\              .
//  /OE:                                   .                                    \             .                                                                                                                                                                        
//         '0'                             .                                     \------------.----------
//                                         .                                                  .                
//         '1'                             .                          /--------\              .                                                     
//  LATCH:                                 .                         /          \             .                                                                                                                                                                        
//         '0' ----------------------------.------------------------/            \------------.----------               
//                                         .                                                  .                           
//         '1' ----------------------------.--------------------------------------------------.---\ /-------                                                                
//  ADDR:                                  .       0                                          .    x     1                                                                                                                                                           
//         '0' ----------------------------.--------------------------------------------------.---/ \-------   
//                                         .                                                  .
//         '1'       /---\ /---\ /---\ /---.\ /---\ /---\ /---\                               .                                                                                           
//  RGB1:           / p1  x  p2 x  p3 x    . x p62 x p63 x p64 \                              .                                                                                                                                                                                           
//         '0' ----/-----/ \---/ \---/-\---./ \---/ \---/ \-----\-----------------------------.------------------
//                                               .                                            .
//         '1'       /---\ /---\ /---\ /---.\ /---\ /---\ /---\                               .                                                                                           
//  RGB2:           / p1  x  p2 x  p3 x    . x p62 x p63 x p64 \                              .                                                                                                                                                                                           
//         '0' ----/-----/ \---/ \---/-\---./ \---/ \---/ \-----\-----------------------------.------------------
//                                         .                                                  .
//
// So before we get into anything fancy, let's try lighting up a single pixel on a single line.
// Let's start by creating a module:
`default_nettype none

module hub75_demo_driver
#(
  /* Tang Nano 9K Board - featuring GOWIN FPGA: GW1NR-LV9 QFN88P (rev.C) */
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT_MS = 10 // make startup delay of 10 [ms] for our LCD screen
)
(
  input   wire      clk,
  input   wire      rst,
  output  reg[4:0]  ADDR, // ref. A, B, C, D and E pins
  output  reg       OE,   // active-low
  output  reg       LATCH, // ref. LAT pin
  output  reg[2:0]  RGB1, // ref. R1, G1 and B1 pins - [0] red; [1] - green; [2] - blue; (top row)
  output  reg[2:0]  RGB2, // ref. R2, G2 and B2 pins - [0] red; [1] - green; [2] - blue; (bottom row)
  output  wire      clk_out // ref. CKE pin
);
localparam  PIXEL_COLUMNS = 64; // screen width in pixels 
localparam  PIXEL_LINES   = 32; // screen height in pixels/2

// Our module receives two input ports the main clk signal and the rst port which is connected to the reset button. Other than that all the other ports are the outputs of the LED panel.
// ADDR is a 5-bit port connected to the A, B, C, D and E inputs of the LED panel, OE and LATCH are connected to their corresponding control lines. Next, we have RGB1 that controls the top half of the screen and RGB2 that controls the rows in the
// bottom half of the screen. Finally, clk_out is the signal to control the clock of the LED panels shift registers, every pulse of the clk_out port will shift one pixel into the screen.
// Inside the module, we define two local parameter constants, one to store the number of pixels per column, and one to store the number of row pairs the screen has.
// Next, let's set up some registers:
reg [6:0] counter = 0;
assign ADDR = 5'b00000;
assign RGB1 = (counter == 63) ? 3'b001 : 3'b000;
assign RGB2 = 3'b000;
// We will use the 7-bit counter as a pixel counter to know where we are in the frame. In terms of address, we will hard-code this to a value of: 0, only displaying data on the first row pair. For the pixel color pins, we will set the bottom half
// of the screen to always 0 so it will stay not lit up, and for the top half of the screen we will only light up the last shifted in pixel (when counter == 63). We set RGB1 to 001 meaning only the least significant (red) subpixel will be lit.

// With these two modules (clock_divisor and oe_controller), we can go back to our main module and integrate them:
wire clk_master;
clock_divisor clkdiv(
  .clk(clk),
  .clk_out(clk_master)
);
assign clk_out = (counter < PIXEL_COLUMNS) ? clk_master : 1;

oe_controller oe_ctrl(
  .clk(clk_master),
  .rst(rst),
  .cnt(counter),
  .OE(OE)
);
// For the latch cycle at the end of a row, we will leave the clock high, but everywhere else we are directly connecting the external shift registers clock to this clock divider.
// As for the OE (output enable) pin, we connect it to our controller module, along with our subdivided clock and the pixel counter we created earlier.

reg LAT_EN = 1;
always_ff @(negedge clk_master) begin 
  if(!rst) begin
    LATCH   <= 0;
    LAT_EN  <= 1; 
    counter <= 7'd0; 
  end else begin 
    counter <= counter + 7'd1;
    if(counter == PIXEL_COLUMNS & LAT_EN) begin 
      LATCH <= 1;
    end else if(counter == PIXEL_COLUMNS+1 & LAT_EN) begin 
      LATCH   <= 0;
      counter <= 7'd0; 
      LAT_EN  <= 0;
    end
  end
end
// We start with our flag to update LATCH set high (LAT_EN) We then have our main always block which will update our pixel counter and control the latch signal.
// For 64 cycles we don't need to do anything, as we are not changing colors here per pixel, after all the pixels have been shifted in we set the LATCH pin high, and then on the next clock-divided cycle we set the LATCH back low and disable the
// LAT_EN flag, causing us to only do a single update to the screen.

endmodule 


// Next, let's create some helper modules to take care of the other control signals clk_out and OE:
module clock_divisor(
  input   wire  clk,
  output  wire  clk_out
);

reg [11:0] counter = 0;
assign clk_out = counter[11];
always_ff @(negedge clk) counter = counter + 1;
// In this module, we are simply dividing up the clock by a factor of 4096 giving us about 6.5Khz (27Mhz/4096), updating a line requires about 66 clock cycles (64-pixel shifts and two for latching) so we will be at around 100fps for a single 
// line.
// This division is arbitrary, the screen can be updated a lot faster than this, because there is no standard it is hard to say what speed will work for you, but you can play with this value lowering the pixel count from 12-bits to 6-bits or even
// smaller to play with the speed. The HUB75 board I received was able to even run at the full 27Mhz but that is usually not required as it would give you about 25,000 FPS for an entire screen update. Updating the screen too fast, even if it
// handles it, shortens the resolution of the screen brightness as the entire frame is smaller so less time/resolution to be on / off during a cycle.
endmodule

// Speaking of screen brightness, we can play with the duty cycle of the OE pin to adjust the percentage of time the screen is lit up.
module oe_controller(
  input   wire       clk,
  input   wire       rst, 
  input   wire [6:0] cnt,
  output  reg        OE 
);

localparam OE_INTENSITY = 16; // This controls the intensity of the led: value 0-64
always_ff @(negedge clk) begin 
  if(!rst) begin 
    OE = 1;
  end else begin 
    if(cnt < OE_INTENSITY) OE = 0; else OE = 1;
  end
end
// OE is usually an active low signal, so during a reset we will set it high, blanking the screen, and other than that we will check where we are in the process from 0-64 pixels currently being shifted in, and if the current pixel count is lower
// then the intensity we will light up the screen, otherwise it will be turned off.
// So a higher value of OE_INTENSITY means the current row on the screen will be powered for longer. It doesn't actually have to do with the pixels, being shifted in, as all pixels in a row update at the same time (when the LATCH pin is pulled 
// high) so we are using the pixel counter only as a measure for the duration in time of a row update.
endmodule


// Test Result:
//
// With this we can now run our module and you should see a single pixel lit up:
//
// ...
//
// If instead you only see the pixel flash and then turn it off this is ok, after testing multiple boards it seems some boards don't actually, allow you to pulse the OE pin and will only display the data on the first OE pulse requiring you to
// change address lines before displaying a line again.
// The issue is sometimes even more subtle than that, as some boards don't allow you to keep OE low all the time, but rather precisely control when in the cycle it should be on or off in regards to the other signals. For example one of the 
// screens required changing the address line to re-output light, so toggling between two row addresses each frame caused it to work.
// This is another disadvantage in the lack of standardization on these screens, but for most examples, you will be updating the entire screen in each frame anyway so it will work mostly as expected.
// With the proof of concept out of the way, we can now move on to displaying an entire image.