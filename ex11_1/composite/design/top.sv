// < Tang Nano 9K: Composite Video >
//
// In this article, we will look at composite video, more specifically the NTSC standard, and how we can implement it on the Tang Nano. We will be following Adam Gastineau who masterfully developed and documented this project, so without
// further ado, let's get into it.
//
// < Composite Video >
// 
// Composite Video as the name kind of implies is a protocol that combines multiple kinds of data onto the same line. The protocol was developed first for black and white screens that used a ray-gun to blast the front of the screen causing
// it to light up at the point the ray was pointed at.
// The original signal combined two components, luminance (brightness) and sync pulses. The brightness controlled the shade of gray, where 100% luminance would be white and 0% would be black allowing you to create a grayscale image and 
// the sync pulses would be used to tell the ray gun how to move to synchronize it with the signal.
// The way it worked was the ray-gun would sweep from the top left corner of the screen moving right, and then when you get to the end of a row it would need something to tell it to go back to the start of the next row. Kind of like a 
// carriage return on a typewriter, the horizontal sync pulse was used for this, at the end of each frame there is also a vertical sync pulse used similarly to cause the ray gun to return to the top left corner to start a new frame.
// It's a tiny bit more complicated than that since frames were interlaced in two passes. You would first send all the even lines finishing on a half-line and then return to the top for a second pass to draw all the odd lines. These two 
// passes together create one full frame, but the purpose of the pulses is all the same.
// You can think of the ray gun as a sort of light source (LED), the more power you put into it, the brighter it will be (up to the max voltage). We need to both encode sync data and color data, so the protocol splits up the voltage range
// into two sub-ranges with a small area we can use for sending sync data and the rest of the range used as the brightness range.
// For example, typically the complete voltage range is 0v-1v, where a value of zero represents a sync and then there is a small gap to separate the two ranges so it's easier to distinguish between them and then from 0.3v - 1v is the range
// describing the brightness of a pixel with 0.3v being black and 1v being white.
// Now I say "pixel" but we don't really have pixels here, we are dealing with an analog continuous range, controlling a ray gun that is continuously outputting electrons based on the supplied voltage as it moves across the screen. We do
// have a vertical resolution, for example with the base NTSC standard there are 480 visible vertical lines, which is what we control with the sync pulses, but as to how many horizontal pixels, it would be based on the capabilities of the 
// television itself how many horizontal pixels could be deduced.
// Nowadays with composite adapters connected to more modern screen technology, you will have a specific number of pixels which converts to usually something like 600x480, but again this is not part of the base standard and is interpreted
// differently by each screen.
//
// < Drawing Horizontal Lines >
//
// To illustrate the above points, let's take a look at how we would draw a single white horizontal line. To do this we would need something like the following:
//
//        
//                                :                                                             :
//                                :                   BRIGHTNESS INFORMATION                    :
//        |                       :                                                             :
//   1[V] |                       :       /---------------------------------------------\       :   
//        |                       :      /                                               \      :
//        |                       :     /                                                 \     :  
//        |                       :    /                                                   \    :
//        |                       :   /                                                     \   :
//        |                       :  /                                                       \  :
//        |                       : /                                                         \ :
//        |                       :/                                                           \:
// 0.3[V] |    *      *------------                                                             ----------
//        |    |      |   BACK    :                                                             : FRONT 
//        |    |      |  PORCH    :                                                             : PORCH
//   0[V] +    *------*           :                                                             :
//            HORIZONTAL          :                                                             :
//               SYNC             :                                                             :
//
//
// We start with a short pulse at 0v which is called a horizontal sync, it is what would cause the electron beam to retract horizontally starting a new line. After this we have a small section at 0.3v or black roughly the same length as the
// horizontal sync pulse, this is called the back porch. The purpose of this section is to give the beam time to retrace and stabilize on the other side of the screen.
// We then start the color data, here since we are simply drawing a white horizontal line we leave the line at 1v which is the brightest value white. The brightness information lasts for a little under 60 microseconds, and the ray gun would
// travel horizontally across the screen at this time.
// Again during this time, you can put the line at any voltage between 0.3 and 1v to control the brightness at that point along the horizontal. So if we would return the above signal for every line in the image we would get a white screen,
// and if we wanted to create the following pattern on screen.
// 
// ...
//
// Then we would need to send something like the following for each line:
//
// ...
//
// You can play around with the following simulator, and draw in the active area region to update the wave:
//
// ...
// 
// ...
//
// To draw an image you would need to keep track of where the "ray gun" is currently on screen, and based on the brightness value of the pixel at that corresponding point, you would need to set the voltage accordingly between 0.3v and 1v.
// Finally, at the end of each horizontal line, you have another very small section at 0.3v just to give a little padding between the image and the sync pulse.
//
// < Drawing a Frame >
// 
// Drawing a full frame is just drawing horizontal lines with vertical sync pulses to reset the gun to the top of the screen.
// Altogether the NTSC signal can be thought to be comprised of 525 lines, where for interlaced video we first draw the even 262.5 lines and then circle back to draw the odd 262.5 lines.
// We talked above about how the screen knew to return to the beginning of the line when it receives a sync pulse, kind of like a carriage return, but we didn't discuss the vertical feed. The CRT laser would be constantly lowered throughout
// each scanline, moving about half the height of a line in the draw path and the rest during the carriage return.
// By resetting the Y position back to the top in the middle of a line, we are essentially half a line higher than where we were on the first pass. Since the first pass started at this Y but at the left side of the screen, once it got to 
// this position it was already lower.
//
// ...
//
// The angle is greatly exaggerated to illustrate the idea, but you can see by resetting the Y position using a vertical pulse mid-line we essentially offset the whole next "frame" by half a vertical line.
//
// < An NTSC Frame >
// 
// For an entire interlaced frame you would need to construct something like this:
//
//  ...
//
// Blank lines are just video lines with the color set to black (0.3v) throughout the entire line. We know how these lines look, they are comprised of a horizontal sync pulse, the back porch, the active video section, and the front porch.
// We send 262.5 scanlines per field, and it is worth mentioning that the 0.5 scanline from the first field is the half of the scanline with the horizontal sync pulse and the half scanline of the second field is the end of a scanline without
// a horizontal sync.
// Other than that there are these EQ (equalizing) and vertical sync pulses. Each is exactly half a scan line in length and is comprised of a portion at the sync voltage (0v) and a portion at the blanking voltage (0.3v) (diagram below).
// The EQ pulses are short pulses and the vsync pulses are long pulses. Because the only difference between types of syncs is their length (since voltage is already used for other things as we saw), there were typically circuits designed to 
// calculate the length of the pulse. This was commonly done with passive components like capacitors which would build up charge while the pulse is on and discharge when the pulse is off.
// We could then trigger a vertical sync when this capacitor reaches a specific voltage level signifying the charge time was the length required for a vertical sync. The problem here is that before the retrace on an even field, we have a full
// video line, and before the long pulse of the odd field we have a half video line.
// This would essentially throw off the calibration or at least make the decoding circuitry more complicated taking into account the differences per field in the charge generated by the previous frame's horizontal sync pulse and the amount of 
// time after that pulse to the time we send the vsync pulse.
// The equalizing (short pulses) helps with this by leveling the playing field on both sides. Both before and after the vertical sync pulses no matter the field, we send lines with very short pulses (usually half the size of a horizontal pulse) 
// equalizing the decoding circuitry making the process simpler.
//
// Take a look at these pulses next to our standard horizontal scanline:
//
//             |-----------------------------------    ONE SCANLINE   -------------------------------|
//                                                                                              
//                                                              
//        |                                             ACTIVE VIDEO                                          
//   1[V] |                               /---------------------------------------------\        
//        |                              /                                               \      
//        |                             /                                                 \     
//        |                            /                                                   \    
//        |                           /                                                     \   
//        |                          /                                                       \  
//        |                         /                                                         \ 
//        |                        /                                                           \
// 0.3[V] |    *      *------------                                                             ------
//        |    |      |   BACK                                                                   FRONT 
//        |    |      |  PORCH                                                                   PORCH
//   0[V] +    *------*                                                                          
//            HORIZONTAL                                                                         
//               SYNC                                                                            
//
//                                                           
//        |                        
//   1[V] |                        
//        |                        
//        |                        
//        |                        
//        |                        
//        |                        
//        |                        
//        |                        
// 0.3[V] |    *   *---------------------------------------*                             *---------
//        |    |   |                                       |        LONG PULSE           |
//        |    |   |            SHORT PULSE                |                             |
//   0[V] +    *- -*                                       *-----------------------------*                                  
//                                                                      
//                                                                      
//
// If we were to compare the pulse lengths (the amount of time at 0v for each type of pulse) then the short pulse is about half the time of a horizontal pulse and the long pulse is the length of a half scanline subtracting about the length of a horizontal pulse.
// If you want exact numbers, here are some rough estimates:
//
// Full scan line: 63.55µs
// Front porch before horizontal pulse: 1.5µs
// Horizontal pulse width: 4.76µs
// Back porch after horizontal pulse: 4.44µs
// Video Section: 52.6µs
// Short pulse on width: 2.54µs
// Short pulse off width: 29.235µs
// Long pulse on width: 27.32µs
// Long pulse off width: 4.45µs
//
//
// < Progressive Mode >
//
// The original standard we talked about uses a 480i resolution, meaning it has 480 (visible) vertical lines that are rendered interlaced. But understanding the technology and how it works allowed people to "hack" the standard making it easier to implement.
// In the base standard, you have things like half-lines and interlacing to deal with and you only get a frame rate of 30fps (and not 60) since it takes two fields per frame.
// To get higher refresh rates and simpler drawing logic people removed the half-line causing the frame to not interlace vertically, This meant that the first field and second field were one on top of the other essentially giving you only a single field updating
// at 60fps.
// This comes at the cost of lowering the vertical resolution since each field has only 240 visible lines instead of 480. The lines are also slightly spaced apart without the interlacing causing the retro black lines between rows.
// Retro consoles like the NES used this technique and send the following field as their frames:
//
// ...
//
// As you can see a lot simpler, you may have noticed, that because we no longer have a difference between the two fields we no longer need the equalizing pulses (short pulses) simplifying it further.
// We essentially have the vertical sync and regular horizontal scanlines, and we send a constant 262 fields instead of trying to match the 262.5, but because of the sync pulses (and maybe the almost mechanical nature of the protocol), this seemed to work.
// We will be implementing this format of NTSC on the Tang nano. So without further ado let's get into the build.
//
//
// < The Electronics >
//
// The first practical issue we need to deal with is generating the analog signal from our FPGA.
// One way we can accomplish this is by using a sort of voltage divider via a resistor network. This is cheap, would allow us to enter values in parallel and they are super fast to react, being comprised of only resistors.
// If you have seen a resistor ladder (e.g. R-2R) then you probably know where we are going with this, but if not we will start from the beginning.
// A voltage divider at its simplest could look something like this.
//
//                                 V-OUT
//                                   ^
//                                   |                    
//                                   |
//                                   | 
//               +----------+        |        +----------+
//  V-IN >-------|    R1    |--------*--------|    R2    |--------| GND
//               +----------+                 +----------+
//      
//                    
//                                   R1
//                V-OUT =  V-IN x --------- 
//                                 (R1+R2)
//
//
// In our case, we have a voltage source of 3.3v so that would be V-In, and if we take for example 1k Ω for R1 and a 2k Ω resistor for R2 We can see that we would get 3.3 * (2/3) or 2.2 volts, exactly 2/3 the voltage.
//
// Resistors in series can be simplified into a single resistor by just combining the resistance values. So our example above would be equivalent to a single 3k Ω resistor between V-in and Gnd. Using Ohm's law we can calculate the current through this circuit 
// as I = V/R or I = 3.3/3000 = 0.0011 amps.
// Now going back to the original schematic, we know R1 is 1000 Ω, so to calculate the voltage drop over R1 we can again use ohms law and get V = IR or V = 0.0011 * 1000 = 1.1 volts. If R1 has a voltage drop of 1.1 volts then we can see that the voltage right 
// after is 3.3-1.1 or 2.2 volts, like we got from the formula above.
//
// The last piece of this puzzle is the way resistors behave when they are in parallel. If I have two or more resistors in parallel then to calculate the equivalent resistor that you can use to simplify the circuit you have to take the reciprocal of the sum of 
// reciprocals of each resistor. Quite a mouthful, but essentially you take the reciprocal of each resistor, sum all those numbers up, and then take the reciprocal of the sum.
// So for example, if I have 3 resistors Ra, Rb, and Rc all in parallel, then I could essentially replace them with a single resistor R as follows:
//
//                  +----------+                  
//             *----|    Ra    |----*                
//             |    +----------+    |                               
//             |                    |     
//             |    +----------+    |                                  +----------+ 
//   V-IN >----*----|    Rb    |----*-----| GND            V-IN  >-----|    R     |--------| GND      
//             |    +----------+    |                                  +----------+     
//             |                    |   
//             |    +----------+    |   
//             *----|    Rc    |----*
//                  +----------+     
//         
//                    
//                             1
//                R  = -----------------
//                       1     1     1
//                      --- + --- + ---
//                       Ra    Rb    Rc  
//                        
// So we know that having two resistors in series divides the voltage proportionally between the two, and we know that adding multiple resistors in parallel decreases the effective resistance.
// Composite video has an input impedance of 75 Ω and our signal comes from our voltage source and is attached on the other end to our ground, so the screen itself can act as the basis for the second resistor in our voltage divider R2. 
//
//                                                                                                                                                                                                                                            
//                                                                                                                                                                                                                                                     
//                                                                                                                                                                                                                                                                 
//                                                   +------------                                                                                                                                                                                                                                                
//                                                   |  SCREEN                                                                                                                                                                                               
//   +--------------+                                |                                                                                                                                                                                             
//   |  FPGA        |         +----------+           |                                                                                                                                                                                    
//   |              |---------|    R     |-----------|-----*                                                                                                                                                                                                        
//   |              |         +----------+  ANALOG   |     |                                                                                                                                                                                   
//   |              |                        INPUT   |   +---+                                                                                                                            
//   |              |                                |   |   |                                                                                                                                                          
//   |              |                                |   |   |                                                                                                                                                                                     
//   +--------------+                                |   |   | 75 Ω                                                                                                                                                                                                                                                           
//                                                   |   |   |                                                                                                                                                                                                                                                        
//                                                   |   +---+                                                                                                                                                                                                                                                             
//                                                   |     |                                                                                                                                                                                                                                                                         
//                                                   |     |                                                                                                                                                                                                 
//                                            *------|-----*                                                                                                                                                                                         
//                                            |      |
//                                            |      +------------
//                                           ---
//                                           GND
//
//
// The above setup would only let us output a very specific voltage since the resistor is constant (and we can do 0v).
// To get a more dynamic range we add multiple resistors connected on one end to our FPGA's pins and the other end to the composite signal.
//
//                                                           +------------                                                                                                                                                                                                                                                
//                                                           |  SCREEN                                                                                                                                                                                               
//   +--------------+                                        |                                                                                                                                                                                             
//   |  FPGA        |         +----------+                   |                                                                                                                                                                                    
//   |              |---------|    R     |------*------------|-----*                                                                                                                                                                                                        
//   |              |         +----------+      |   ANALOG   |     |                                                                                                                                                                                   
//   |              |         +----------+      |    INPUT   |   +---+                                                                                                                            
//   |              |---------|    R     |------*            |   |   |                                                                                                                                                          
//   |              |         +----------+      |            |   |   | 75 Ω                                                                                                                                                                                     
//   |              |         +----------+      |            |   |   |                                                                                                                                                                                                                                                           
//   |              |---------|    R     |------*            |   +---+                                                                                                                                                                                                                                                     
//   |              |         +----------+                   |     |                                                                                                                                                                                                                                                          
//   |              |                                        |     |                                                                                                                                                                                                                                                                         
//   |              |                                        |     |                                                                                                                                                                                                 
//   |              |                                 *------|-----*                                                                                                                                                                                         
//   |              |                                 |      |
//   |--------------+                                 |      +------------
//                                                   ---
//                                                   GND
//
// All the resistors connected to a pin that is high, are essentially in parallel as they have one side connected to 3.3v, and the other sides are all connected at the composite video signal's analog input. All resistors connected to low pins are essentially
// in parallel with R2 - from our voltage divider - as they have one end at the same composite signal point, but now their other end is at GND, just like the screen itself. So in terms of our voltage divider by switching the pins on or off, you essentially move
// the resistor from being in parallel with R1 to being in parallel with R2.
// 
// This as we saw will lower one side to go up in resistance and the other side to go down allowing us to dynamically control the resistance, which in turn controls the voltage.
//
// We have constructed a little simulator here where you can press on the switches and then jump to the different views using the "Arranged" or "Equivalence" buttons to see how the resistors are practically arranged and how they can be simplified using both the 
// principles we saw above.
//
// ...
//
// Instead of a switch, we will be connecting each of them to a pin on the FPGA and we will internally either pull the line high to 3.3v or low to ground acting as the switch. If we map this data into a table you can see we have our 0 volts for sync pulses, we 
// have our 0.3 volts (or pretty close to it) for blanking (also for black), and then we have 4 more voltage levels that will be shades of grey and we have the 1 volt for white. Essentially 6 different shades of grey that can be used for drawing on our composite
// signal.
//
// +---------------------------------------------------------------+
// |    R1 - 270	        R2 - 330	       R3 - 470    	Voltage    |
// | 			 OFF              OFF              OFF       0.000 Volts |
// | 		   OFF              OFF              ON	       0.316 Volts |
// | 	     OFF              ON		           OFF       0.450 Volts |
// |       ON			          OFF              OFF       0.550 Volts |
// |       OFF             	ON	             ON	       0.766 Volts |
// |       ON		            ON	             OFF       0.867 Volts |
// |       ON	              ON	             OFF       1.001 Volts |
// |       ON	              ON	             ON      	 1.317 Volts |
// +---------------------------------------------------------------+
//
// The last option exceeds the voltage rating of the spec so we don't get to use that option, but other than that it checks all the boxes and even has a good spread around the area that is important to us and no wasted values between 0-0.3 volts.
// This isn't by chance, Adam created a solver to work out the best values using a 3-resistor configuration and our 3.3v voltage source.
// You can use any of the 3.3v IO pins to control the resistor network, we will be using pins 49, 31, and 32.
//
// ...
//
// * Pin 49 - the 270 Ω resistor
// * Pin 31 - the 33o Ω resistor
// * Pin 32 - the 470 Ω resistor
//
// We connect the other end of all the resistors together into a single signal which will be our composite video signal.
//
// ... 
//
// I didn't personally have a 270 Ω resistor but putting what we learned into practice, I can get a pretty convincing 270 Ω resistor by putting a 680Ω and 470Ω resistor in parallel (277 Ω, but close enough for this test).
// A composite cable has two wires inside, the composite signal wire which is highlighted above, and a ground wire which can be taken from the next pin on the FPGA.
//
//
// Implementing a PoC
//
// Before we start drawing full images, I found it extremely helpful to implement a very basic version first, which just shows the minimum requirements for getting something on screen.
// The main thing we need to do to get a picture on the screen is to send the correct sync pulses and blanking phases. With those in place, we will have frames being drawn, and then like we saw above it's just a matter of deciding what we want to draw.
// Before we get into a more clever and concise solution, let's implement the naive approach in our PoC as I think it makes the logic easy to understand.
//
//
// Create a file called composite_count_test.v and let's start with a module that will keep track of where we are in the frame:


// < Running a Test >
// 
// To test it we need a constraints file and a top module.
//
// For the top module we will need to control these resistors using our composite video flags. So in a new file: (top.v)

`default_nettype none

module top
#(
  /* Tang Nano 9K Board - featuring GOWIN FPGA: GW1NR-LV9 QFN88P (rev.C) */
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037  // external clock source, period in [ns], 
)
(
  input wire refclk,
  // We start off with our resistors all at 0v, ...
  output reg output_270ohm = 0,
  output reg output_330ohm = 0,
  output reg output_470ohm = 0
);

wire hsync;
wire vsync; 
wire hblank;
wire vblank;
wire active_video;
wire [9:0] y;
// ... and just instantiate an instance of our composite counter module.
composite_count_test cc(
  .clk(refclk),
  .hsync(hsync),
  .vsync(vsync),
  .hblank(hblank),
  .vblank(vblank),
  .active_video(active_video),
  .y(y)
);

always @(posedge refclk) begin
  if(hsync | vsync) begin
    output_270ohm <= 0;
    output_330ohm <= 0;
    output_470ohm <= 0;
  end
  else if(hblank | vblank) begin 
    output_270ohm <= 0;
    output_330ohm <= 0;
    output_470ohm <= 1; 
  end
  else if(active_video) begin 
    case({y[4], xCounter[6]}) // instead of the case being on y[4:3] try changing it to case ({y[4], xCounter[6]}).
      2'b00: begin 
        output_270ohm <= 0;
        output_330ohm <= 0;
        output_470ohm <= 1; 
      end
      2'b01: begin
        output_270ohm <= 1;
        output_330ohm <= 0;
        output_470ohm <= 0;         
      end
      2'b10: begin
        output_270ohm <= 0;
        output_330ohm <= 1;
        output_470ohm <= 1;         
      end
      2'b11: begin
        output_270ohm <= 1;
        output_330ohm <= 1;
        output_470ohm <= 0;         
      end
    endcase
  end
end
// If any of the sync flags are on we need to set the voltage to 0 and if any of the blank flags are set we need to send 0.3v by connecting only the 470 ohm resistor.
// Finally, we have the active video section where we can select any of the 6 voltage options between 0.3-1 we can reach with our resistor network.
// Here we will be using just 2 of the bits from our scanline counter to create a repeating pattern of 4 options in increasing brightness. (Just remember you can't set all resistors high as they will exceed 1V and
// you can't set them all low as it would be considered a sync pulse).
//
// Running this you should get something that looks like the following:
//
// ...
// 
// We can easily distinguish our four different shades of gray here, and counting we can see we have about 29+ lines which if we multiply by 8 (since we are reading bits 4 & 5 of the scanline counter) we can see we 
// have pretty much all our 240 visual lines.
//
//
// < The X Direction >
//
// The last thing I want to demonstrate is controlling pixels in the horizontal direction. This is already not part of the NTSC standard and is controlled by the speed at which both us and the screen can react to changes.
// So we can decide there are 4 pixels in the X direction or 400, and it's arbitrary as the screen expects a constant continuous value.
// To demonstrate this let's add a counter to our 'top' module to count in the x direction:
reg [7:0] xCounter = 0;
always_ff @(posedge refclk) begin 
  if(hsync)
    xCounter <= 0;
  else
    xCounter <= xCounter + 1; 
end
// We reset the counter whenever we have a horizontal sync just to keep the frame from scrolling and to have each line aligned, although I do recommend trying with a counter that doesn't reset to see how it will create a scrolling pattern. 
// Next inside our case statement, instead of the case being on y[4:3] try changing it to case ({y[4], xCounter[6]}). We are still only using two bits to cycle through 4 colors, but we are changing based on the y direction only based on the
// top bit, which will make our lines twice as high, and now the other bit which controls the color will be based on the 7th bit of our x counter which updates every 64 pulses (2.3µs). If we know that the entire video section is about 
// 1429 clock cycles wide then this is about a 1/23th of the screen's width. For example, if the screen's width is 256 pixels wide then this would mean each square is about 11-12 pixels wide.
//
// Running this updated code should give you a picnic pattern like the following:
// 
// ...
//
// The squares are a bit wider than they are tall since the height is 8 scan lines / ~240 (1/30) and the width is like we saw is closer to 1/23.
// With that our PoC is complete and we can move onto creating a project that can draw an image.

endmodule

