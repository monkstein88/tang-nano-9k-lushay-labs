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
//
//
// < Displaying an Image >
//
// To display a full image on the screen we simply need to do the same process as updating a single line, just 32 times. We also want to dynamically set the RGB value of each pixel based on our image.
// The easiest way to do this is with a frame buffer. By storing the entire image in memory, we can look up any RGB value we need, for both the top half of the screen and the bottom half, based on our pixel counter and address lines, controlling 
// the RGB output.
// We have 64x32 pixels and for each pixel, we have 3 bits of data giving us a total minimum framebuffer size of 768 bytes.
//
//   64 [columns] x 64 [rows] x 3 [rgb] = 12288 bits = 1536 Bytes  -- 2 rows   
//   64 [columns] x 32 [rows] x 3 [rgb] = 6144 bits = 768 bytes -- 1 rows
//   
// To make it easy to look up, instead of storing the data in bytes, we will set up a ROM with 2048 3-bit values, which is 64 pixels x 32 rows x 3 bits per pixel, which is what we need for each half of the screen.
// The choice of having two separate ROMs for each half of the screen versus a single ROM for both lines is an arbitrary decision and just makes the creation of the ROM slightly simpler instead of pairing lines, this is negligible though as we 
// could have stored 2048 6-bit values where each value stores a pixel for both the top and bottom half.
//
// To load our data we can use things like 'readmemh' or 'readmemb' like we have done in the past, but for this example, we will generate a static verilog ROM to showcase another method.
// So let's start with a script that will take in an image and convert it into the ROMs we will need to display an image.
// 
// Next, we can create our main module:
//
//
// < Image Hub75 Driver >
//
// We will be using the same clock_divisor from the proof of concept, but this time instead of having static color values for the RGB signals we will want to dynamically load them based on the current pixel being shifted out. You may want to
// make your clock divisor a bit faster since we will be updating the entire screen instead of just a row:
//
//
// < Extending the Color Space >
//
// Up until now, we have been only using the 8 colors we can get from directly combining the RGB LEDs. For reference, these are the 8 colors:
//
// ...
// 
// These are the only colors the panel can directly emit, but by rapidly changing between these colors with different proportions of each, we can cause our eyes to perceive a wider spectrum of colors.
// The two factors that play a role in the number of colors that can be generated is our pulse resolution and the refresh rate. These two factors kind of work against each other, for example with a higher resolution of 10-bits per channel, would 
// mean we need to go through a period of at least 1024 cycles to accurately give each part of the colors being mixed the correct ratio.
// Having a higher period to the cycle means the frequency for the entire sequence goes down. If the frequency goes down too much then it will be very noticeable that different colors are being switched between instead of seeing a blended color.
// And when I say it needs to be fast I don't mean like a standard 60 fps, I am talking about the entire color switching sequence needs to fit preferably in a single 60fps update (above 60hz).
// So again, higher resolution of color, means more times we need to fully update the screen before we get out a single color, requiring a higher clock speed to get out a frame without flickering.
// The next thing we need to do is calculate which of the colors to mix and how. This can be accomplished with a simple counter to know where we are in our cycle.
// For example, if we are using 4-bit channels giving us 16 options per channel, then if the value for the red channel is 6, we would light up the red pixel for the first 6 screen updates, and then for the next 10 the red led will be off, giving 
// us the proper ratio by just comparing the channel value to our cycle counter.
// You can use the tool below to understand which colors need to be mixed and at what ratio to reach a desired color.
//
//  ...
// 
// The number of colors grows rapidly as even adding a single bit not only doubles the number of options for a single channel, but that change compounds together with the number of new total options between channels giving an equation as follows:
//
// (2<num_bits> )^3
//
// So with 1 bit of color resolution, we had 8 colors:
//
// ...
// 
// By raising our resolution to 2 bits per channel we get 64 colors:
// 
// ...
// 
// For our next example let's experiment with implementing this 2-bit color into our image viewer.
//

module hub75_image_driver
#(
  /* Tang Nano 9K Board - featuring GOWIN FPGA: GW1NR-LV9 QFN88P (rev.C) */
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT_MS = 10 // make startup delay of 10 [ms] for our LCD screen
)
(
  input   wire      clk,
  input   wire      rst,
  output  reg[4:0]  ADDR  = 5'd0, // ref. A, B, C, D and E pins
  output  reg       OE    = 1'd1,   // active-low
  output  reg       LATCH = 1'd0, // ref. LAT pin
  output  reg[2:0]  RGB1, // ref. R1, G1 and B1 pins - [0] red; [1] - green; [2] - blue; (top row)
  output  reg[2:0]  RGB2, // ref. R2, G2 and B2 pins - [0] red; [1] - green; [2] - blue; (bottom row)
  output  reg      clk_out = 1'd0 // ref. CKE pin
);

localparam  PIXEL_COLUMNS = 64; // screen width in pixels 
localparam  PIXEL_LINES   = 32; // screen height in pixels/2
localparam  BRIGHTNESS    = 5'd31;

reg [6:0] pixelCounter   = 7'd0;
reg [4:0] displayCounter = 5'd0;

// With these two modules (clock_divisor and oe_controller), we can go back to our main module and integrate them:
wire clk_master;
clock_divisor clkdiv(.clk(clk), .clk_out(clk_master));
// So far, it is pretty similar to the previous driver, we have a counter for the current pixel, a counter for the OE signal display time and our clock divider.

// Next in ourtop module we can replace our existing framebuffer with the 2-bit variant:
reg [1:0] colorCycle = 2'd0;
framebuffer2Bit buffer(
  .clk(clk),
  .column(pixelCounter[5:0]),
  .ADDR(ADDR),
  .RGB1(RGB1),
  .RGB2(RGB2),
  .colorCycle(colorCycle)
);

// Finally our modified state machine for refreshing the entire screen instead of a single line:
localparam SHIFT_DATA  = 0;
localparam LATCH_DATA  = 1;
localparam SHOW_PIXELS = 2; 
localparam SHIFT_ADDR  = 3;

reg [1:0] state = SHIFT_DATA;

always @(posedge clk_master) begin 
  case(state)
    // The first state is to shift out the 64 pixels per line: 
    SHIFT_DATA : begin  
      if(~clk_out) begin 
        clk_out <= 1'd1; 
      end else begin 
        clk_out <= 1'd0;
        if(pixelCounter == PIXEL_COLUMNS - 1) begin 
          state <= LATCH_DATA; 
        end else begin 
          pixelCounter <= pixelCounter + 7'd1;
        end
      end
    // Data is updated during the falling edge and read by the panel on the rising edge, so we start with the clock low for one cycle, and then on the next signal when the data is read we update the pixelCounter so that the framebuffer will 
    //load the next byte on the next cycle. 
    end 
    // If we have completed all 64 pixels we move to the LATCH_DATA state:
    LATCH_DATA : begin 
      if(~LATCH) begin 
        LATCH <= 1'd1;
      end else begin 
        LATCH <= 1'd0;
        OE <= 1'd0; 
        state <= SHOW_PIXELS;
      end
      // In this state we want to first set the latch signal high - this will latch in the data - and in the next clock cycle, we will set the latch back low and start displaying it to the screen by pulling OE low.
    end
    SHOW_PIXELS : begin 
      displayCounter <= displayCounter + 5'd1;
      if(displayCounter == BRIGHTNESS) begin 
        OE <= 1'd1; 
        displayCounter <= 5'd0;
        state <= SHIFT_ADDR;
      end
      // The SHOW_PIXELS state simply keeps the OE low for a desired number of frames, the higher the number of frames the brighter the panel will be but the longer each screen update will take. The entire screen update is pretty fast, even 
      // with 32 clock-divided signals we still have about 650fps for the entire screen, anything above 60hz should be smooth enough not to have any noticeable flicker.
    
      // (<clock speed>/<clock divider>) / (<cycles per line>*<num lines>)
      //
      // Where:
      // <clock speed> - 27Mhz or 27,000,000
      // <clock divider> - 16
      // <cycles per line> - 163 = 128 for pixels, 2 for latch, 32 for OE and 1 for addr
      // <num lines> - 16 line updates (each updates 2 lines)
      //
      // ((27000000/16) / ((128+2+32+1)*16) = 647 updates per second
    end
    // The final state updates the ADDR register, moving to the next row on the screen:
    // And then last but not least we need to increment the color cycle counter every time we finish updating the entire screen, which can be done in the SHIFT_ADDR state:
    SHIFT_ADDR: begin 
      ADDR <= ADDR + 5'd1; 
      pixelCounter <= 7'd0;
      state <= SHIFT_DATA;
      if(ADDR == 5'd31) begin 
        colorCycle <= colorCycle + 2'd1;
        if(colorCycle == 2'd2) begin 
          colorCycle <= 2'd0;
        end
      end
    end
  endcase 

end

endmodule 


// Next, let's create some helper modules to take care of the other control signals clk_out and OE:
module clock_divisor(
  input   wire  clk,
  output  wire  clk_out
);

reg [4:0] counter = 0;
assign clk_out = counter[4];
always_ff @(posedge clk) counter <= counter + 1;
// In this module, we are simply dividing up the clock by a factor of 4096 giving us about 6.5Khz (27Mhz/4096), updating a line requires about 66 clock cycles (64-pixel shifts and two for latching) so we will be at around 100fps for a single 
// line.
// This division is arbitrary, the screen can be updated a lot faster than this, because there is no standard it is hard to say what speed will work for you, but you can play with this value lowering the pixel count from 12-bits to 6-bits or even
// smaller to play with the speed. The HUB75 board I received was able to even run at the full 27Mhz but that is usually not required as it would give you about 25,000 FPS for an entire screen update. Updating the screen too fast, even if it
// handles it, shortens the resolution of the screen brightness as the entire frame is smaller so less time/resolution to be on / off during a cycle.
endmodule

// To retrieve the pixel data we will create a framebuffer module to interface with the two generated ROMs:
// The module receives the current column and address, where column is the pixel index in the x direction which is a value between 0-63 and the address lines is the row number which has a range of 0-31 combining these two gives us a 11-bit 
// index between 0-2047 that we can use to index each of the ROMs' values. We then output the RGB values for each line directly from the ROMs.


// < Implementing the Color Mixing
// 
// To implement the color mixing itself we really only need a cycle counter to know where we are in our color cycle. For 2 bits per channel, we need a counter of at least 2 bits to have enough resolution to represent each of the values.
// Then on a per-channel basis we can easily just compare the 2-bit color value to the 2-bit counter value and see if the LED should be lit or not.
module framebuffer2Bit(
  input   wire       clk,     // main clock
  input   wire [5:0] column,  // column index (6 bits for 64 pixels)
  input   wire [4:0] ADDR,    // ADDR input
  output  wire [2:0] RGB1,    // RGB1 output 
  output  wire [2:0] RGB2,   // RGB2 output 
  input   wire [1:0] colorCycle 
);

wire   [10:0] addr_rom; 
assign addr_rom = {ADDR, column};

wire [5:0] topRGB;
wire [5:0] bottomRGB;

ROMTop     rom_low(.clk(clk), .addr(addr_rom), .data(topRGB));
ROMBottom rom_high(.clk(clk), .addr(addr_rom), .data(bottomRGB));

assign RGB1 = {
  (colorCycle < topRGB[5:4]),
  (colorCycle < topRGB[3:2]),
  (colorCycle < topRGB[1:0])
};

assign RGB2 = {
  (colorCycle < bottomRGB[5:4]),
  (colorCycle < bottomRGB[3:2]),
  (colorCycle < bottomRGB[1:0])
};
endmodule
// The new frame buffer is almost identical to the previous one except now we have an extra 2-bit input port for the new color cycle counter. Inside we can no longer connect the RGB lines directly to the ROM as they are not the same width anymore.
// So we connect new 6-bit wires to the ROMs and the real conversion is what happens next. If we take a look at a single channel from RGB0 for example the red channel:
//
// (colorCycle < topRGB[1:0])
//
// We are just comparing our color value with the counter, if our color value is larger then we light the pixel up. Since we only have 4 options per color we can write out the options pretty easily:
//
// +---------------+------------+------------+------------+
// |  Color Value  |  Cycle #1  |  Cycle #2  |  Cycle #3  |
// |      0        |     0      |     0      |     0      |
// |      1        |     1      |     0      |     0      |
// |      2        |     1      |     1      |     0      |
// |      3        |     1      |     1      |     1      |
// +---------------+------------+------------+------------+
//
// The number of cycles we need for a complete color is 2n - 1, where n is the number of bits per channel, the -1 is because the first two cases use the same bit for their value.



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

// ... 
// 
// Running this now you should be able to see many more colors than what we had before:
//
// ...
// 
// Comparing It again to our reference colors, you can see that we have a pretty close match to the colors, at least the brighter colors:
// 
// ...
//
// LEDs emit light, so it's harder to persist a dark color using this method, this causes colors like grey to appear white and brown to look more orange or red. Currently, we are also driving our LEDs linearly for all channels equally, but due to the
// differences in perceived brightness at different levels and colors, these color values can be adjusted to give them a more calibrated appearance.
//
// This is known as a Gamma correction, which essentially adjusts the brightness of a color to better match how it will be seen by our eyes. I don't think this is worth doing in every application, when remapping the color space you lose some resolution, 
// especially in a small 2-bit configuration. Think of it as selectively darkening colors, but if we only have 64 shades of color and you darken some of them there starts to be more overlap (as we have more dark colors, with fewer options there to represent
// them using our 2-bits).