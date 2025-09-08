// < Tang Nano 9K: I2C, ADC and Micro Procedures >
//
// Up until now we have been dealing with all our procedural tasks by creating state machines that would advance step by step through a process. This is great for simpler tasks, but for more complex tasks it can grow out of hand 
// quickly if proper care isn't made to craft the correct building blocks.
// Think about explaining a simple circuit like a 4-bit adder, if your building blocks include a full-adder then it can be explained as 4 full adders chained together. Take the same circuit except your building block is logic gates
// it now requires 20 logic gates to create the 4-bit adder, and if we go down a layer to transistors we will have 40-50 transistors in our diagram.
// The same idea is true with procedural tasks, if you have the right "building blocks" or sub-tasks, then composing the process because both easier, cleaner and can eliminate repetition or wasted resources.
// In this article we will go through this process while integrating the ADS1115 ADC with the Tang Nano 9K over I2C, this will both add two new capabilities to our toolbelt (I2C & ADC) as well as a methodology which can be used to
// tackle even larger projects
//
// < The I2C Protocol >
//
// I2C communicates over two wires, one wire is for data and one wire is for a clock. Unlike SPI, where you have a seperate data wire for each direction, in I2C both wires are bidirectional. Another difference is that with SPI if 
// you want to connect multiple peripherals over the same wires you need to add an extra "chip select" or enable pin to select which device the controller is currently communicating with.
// The I2C protocol has addressing built into the protocol, so you can connect multiple devices without requiring more IO from the controller. The standard address size for I2C is 7-bit allowing for potentially 128 different
// addresses (some addresses are reserved but theoretically) and there is also a 10-bit mode (which we won't get into) that would allow up to 1024 for each 2 IO pins.
//
//                        ^ +V                   +---------------+                                                                                                                                                                                                                        
//                        |                      |  Peripheral   |                                                                                                                                                                                                                                 
//                        |                      | Address: 0x4A |                                                                                                                                                                                                                                             
//                       +-+                     |               |                                                                                                                                                                                                                                                                              
//                       |R|     *---------------| SDA           |                                                                                                                                                                                                                              
//   +--------------+    +-+     |               |               |                                                                                                                                                                                                                             
//   |  Controller  |     |      |   *-----------| SCL           |                                                                                                                                                                                                 
//   |              |     |      |   |           +---------------+                                                                                                                                                                                                 
//   |          SDA |-----*------*   |                                                                                                                                                                                                                             
//   |              |            |   |                                                                                                                                                                                                                             
//   |          SCL |-----*------+---*                                                                                                                                                                                                                              
//   |              |     |      |   |           +---------------+                                                                                                                                                                                                                     
//   +--------------+     |      |   |           |  Peripheral   |                                                                                                                                                                                                                                                                                                 
//                       +-+     |   |           | Address: 0x6E |                                                                                                                                                                                                                                                                                                 
//                       |R|     |   |           |               |                                                                                                                                                                                                                                                                                                 
//                       +-+     *---+-----------| SDA           |                                                                                                                                                                                                                                                                                                                
//                        |          |           |               |                                                                                                                                                                                                                                        
//                        |          *-----------| SCL           |                                                                                                                                                                                                                                
//                        v +V                   +---------------+                                                                                                                                                                                                                                  
//                                                                                                                                                                                                                                                                               
//                                                                                                                 
// The way the communication works at the physical layer is that each line is pulled high through a resistor and any of the devices can pull the line low. The devices cannot see who pulled the line low just if the line is high or
// low, so the protocol relies on coordination and addressing to know who is sending / receiving data.
// The controller is always in charge of driving the clock (even when a peripheral is sending data), and data is changed when the clock is low and read when the clock goes high. Changing the data line while the clock is high has 
// a special meaning in I2C and is used to indicate the start / end of a transaction (communication).
// Pulling the data line from high to low while the clock is high signifies a start of transmission and pulling the data from low to high while the clock is high signifies an end of transmission.
// Transactions with I2C can be multiple bytes long, but after each byte is sent the receiving end (either controller or peripheral) acknowledges the byte by sending a zero on the data line.
// So a typical transaction looks like the following:
//
//           START OF TRANSITION
//  
//  CLOCK (SCL) : '1' -----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+                                                                                                                                                                                                                      
//                         |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |                                                                                                                                                                                                   
//                '0'      +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----   ...                                                                                                                                                                                                               
//                                                                                                                                                                                                                                                                          
//  DATA (SDA) '1' ----+                                                                                                                                                                                                                      
//                     |      +-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+                                                                                                                                                                                                                 
//             '0'     +------|   ADDR7   |   ADDR6   |   ADDR5   |   ADDR4   |   ADDR3   |   ADDR2   |   ADDR1   |    R/W    |------------     ...                                                                                                                                                               
//                                                                                                                                 ACK                                                                
//                                                                                                                                  
//                                                                                                                                            
//                                                                                                                                       END OF TRANSITION
//  CLOCK (SCL) : '1'     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----                                                                                                                                                                                                  
//                        |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |     |                                                                                                                                                                                                                          
//                '0' ----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+     +-----+                                                                                                                                                                                                                                                                                                      
//                                                                                                                                                                                                                                                                                                                                                                                                                                            
//  DATA (SDA) : '1'                                                                                                                     +---                                                                                                                                                                                                                                                                                               
//                     +-----------+-----------+-----------+-----------+-----------+-----------+-----------+-----------+                 |                                                                                                                                                                                                                                                                                                               
//               '0'  -|   DATA8   |   DATA7   |   DATA6   |   DATA5   |   DATA4   |   DATA3   |   DATA2   |   DATA1   |-----------------+                                                                                                                                                                                                                                            
//                                                                                                                          ACK                                                                                                                                                                                                                                       
//                                                                                                                                                                                                                                   
//             
// The controller will send the start of transaction event (again by pulling the data low while clock is high), it will then send the 7 address bits MSb first, the last bit in the first byte is a bit to signify if the controller
// wants to read data from the addressed device or write data to the addressed device. A value of '1' is to read data from the device and a value of '0' is to write.
// The peripheral will then ack by sending a zero over the data line, and then the transaction will continue with the next byte being sent over the data line. In the case where the controller is reading the next byte will be sent 
// by the peripheral and the controller will send the ACK and if the controller is writing to the peripheral then the controller will send this data and the peripheral will ACK.
// No matter which device is controlling the data line (controller or peripheral), the clock line is always powered by the controller.                                                                                                                                                                                    
// The data sending can be repeated multiple times to send multiple bytes in the same transaction, just like above after each byte the other side ACKs. Once all bytes of a transaction are sent the controller sends the "end of 
// transmission" event, by pulling the data line high while the clock is high ending the transaction between the two devices.
//
// 🗒️ Side Note: The reason the clock line also uses a bidirectional open-drain configuration even though it is always driven by the controller is to allow for something called clock-stretching which is where the peripheral can 
//               hold the clock pin low not allowing the controller to continue to the next bit until the peripheral is ready which can be useful if the peripheral is busy or needs more time to process a previous instruction.
//               To implement this the controller needs to read the clock line on each bit and make sure the clock went high when it set the clock high to make sure a peripheral isnt pulling it low
//
// With an overview of the I2C protocol we can now dive into the datasheet for the ADC we will be using and start exploring how to interface with it.
//
//
// < The ADS1115 >
// 
// The ADS1115 is a 4-channel 16-bit ADC, this means you can connect up to 4 analog signals to it which it can mux between and it converts a chosen analog value into a 16-bit digital value.
// Let's take a look at the datasheet to get more information on how to drive it.
// On the first page we get a nice simplified block diagram:
//
// ...
// 
// Here you can see the 4 analog inputs go through a mux and two lines go from the mux into the programmable gain amplifier. The reason there are two lines coming out of the mux is because you can use the ADS1115 to measure 
// differential pairs, we will only be using the ADC to measure positive values so the mux will connect the other wire to ground.
// The programmable gain filter then remaps our input value to a predefined FSR (Full-Scale Range), so if you are using low voltage for example max 2 volts you can program that in and then you will get the full 16-bits of
// precision for the range -2 to +2 volts meaning each increment would represent around 0.061 mv (4v range / 216) whereas if you set the range to +- 6v the precision of each increment would be 0.183mv (12v range / 216). So 
// setting the PGA up as close to your real value range will give you the most accuracy.
//
// ...
//
// The remapped value gets passed to the internal ADC which is then stored in a conversion register for the I2C interface to output. The Alert pin can be used to recieve a notification when the conversion is done / meets a 
// threshold. We won't be using it as you can check the status over the I2C interface so we will get the info there.
// The ADDR pin of the I2C interface is used to setup the address, like mentioned above each I2C peripheral requires an address so that the controller can select it for communication. This pin, depending on how you connect it 
// will set it's I2C address. Here is the table for the different options:
//
// ...
//
// We will be connecting it to VDD so the address we will need to request is 1001000 in binary or 0x73 in hex. (Worth noting there is special care that needs to be taken if connecting the address pin to SDA so refer to the 
// datasheet if that option is chosen).
// The ADC has 4 main internal registers which we use to set up, control and read the conversion values from. The registers are:
//
// 1. Conversion Register
// 2. Config Register
// 3. Low Threshold Register
// 4. High Threshold Register
//
// The first register stores the latest conversion results. The second register is where we setup the ADC, as-well as where we request it to perform a new conversion. The last two registers are used if you want to setup the 
// internal comparator to signal when it is in a certain range. We won't be using the comparator so we mainly need to focus on the first two registers.
// The conversion register is read only and the config register we need to read and write. We need to write the initial config and to trigger a new conversion, and we need to read from it to check when a conversion is ready.
//
// ...
//
// The first bit 'OS' triggers a new conversion when set, and when reading the conversion register it will be a 1 if the ADC is idle (meaning the conversion is done). Next we have 3 bits which control the 'MUX' meaning which 
// analog channel is currently connected to the internal ADC. The next 3 bits we talked about control the 'PGA' (programmable gain amplifier) and the 'MODE' bit sets whether we are in continuous conversion mode or single 
// conversion mode. Like the names suggest in continuous mode the ADC will start a new conversion once it completes the current conversion, and in single shot mode each time you trigger the conversion it will perform only 1 
// conversion.
// The Second byte in the config register is for the comparator, which again we will not be using so we will leave the default values for them.
// We will be using the ADC in single-shot mode, which means the general game plan is we need to write a 1 in the 'OS' bit to start a conversion while setting the 'MUX' to the correct channel, we then need to wait until the 
// conversion is done, which we will see by 'OS' being high while being read. Once the value is ready we need to read the digital value from the conversion register.
// With the high level plan out of the way, how do we actually communicate these instructions to the ADS1115 ?
//
//
// < The Communication >
//
// We basically have two types of commands we can issue, a write command which has the following interface:
// 
// <Address><W> <Register Select> <Optional Data 16-bit> 
//
// By sending the I2C address along with a zero for the read/write bit, it tells the ADC you want to write to a register, the first byte sent after this is the destination register from one of the 4 registers listed above. 
// Once you select a register you can optionally write a value to that register by writing another 2 bytes of data.
// If you don't send data, then the write command simply changes the currently selected register, which is needed for example if you want to select the conversion register in-order to read from it.
// In-order to read a register you need to again make sure you already selected the corrected register by issuing a write command and then you send a read command with the following interface:
//
// <Address><R> <16-bit data>
//
// Now these two interfaces are a bit simplified as for I2C you need to send a start / end transaction event, and there is also an ACK after every byte, so let's take a look at the full process for each of these commands 
// from the datasheet:
//
// The process for writing is as follows:
//
//                            #1                                              #9    #1                                              #9   
//  CLOCK (SCL) : '1' ----+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+                                                                                                                                                                                                     
//                        |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |    
//                        |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |    ...                                                                                                                                                                      
//                '0'     +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--                                                                                                                                                                                                  
//                                                                                                                                                                     
//                                                                                                                                                                        
//                                                                                                                                                                            
//  DATA (SDA) '1'  \        /--\              /--\        /--\  /--\                                                  /--\  /--\        /                                              
//                   \      /    \            /    \      /    \/    \    _                                           /    \/    \      /                                                                                                                                               
//                    \    /  '1' \ '0'  '0' / '1'  \ '0'/  A1 /\ A0  \ R/W      /\'0'   '0'   '0'   '0'   '0'   '0' /\ P1 /\ P0  \    /   ...                                                                                                                                                                                                                                                                     
//             '0'     \--/        \--------/        \--/-----/  \-----\--------/  \--------------------------------/  \--/  \-----\--/                                                                                                                                                                                                                                                                                                                                                                 
//               "Start"                                                    "ACK"                                                  "ACK"                                                                                                                                                                                                                                                                                                                                                      
//               by Master                                                by ADS1115                                            by ADS1115    
//                     :<-------------- Frame 1: Slave Address byte -------------->:<--------- Frame 2: Address Pointer Register ---------->:
// 
//
//                            #1                                              #9                #1                                              #9   
//  CLOCK (SCL) : '1'        +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+              +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +-----                                                                                                                                                                                                  
//  (Continued)              |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |              |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |   
//                   ...     |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |              |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |                                                                                                                                                                         
//                '0'  ------+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--------------+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+                                                                                                                                                                                                   
//                                                                                                                                                                                
//                                                                                                                                                                                   
//                                                                                                                                                                     
//  DATA (SDA) '1'           /--\  /--\  /--\  /--\  /--\  /--\  /--\  /--\              /--+-----\  /--\  /--\  /--\  /--\  /--\  /--\  /--\              /                                                                   
// (Continued)              /    \/    \/    \/    \/    \/    \/    \/    \            /    \     \/    \/    \/    \/    \/    \/    \/    \            /
//                   ...    \D15 /\D14 /\D13 /\D12 /\D11 /\D10 /\ D9 /\ D8  \          /      \ D7 /\ D6 /\ D5 /\ D4 /\ D3 /\ D2 /\ D1 /\ D0 /\          /                                                                                                                                                                                                                                                                             
//             '0'           \--/  \--/  \--/  \--/  \--/  \--/  \--/  \-----\--------/        \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--------/   "End"                                                                                                                                                                                                                                                                                                                                                                                       
//                                                                           "ACK"                                                             "ACK"        by Master                                                                                                                                                                                                                                                                                                                                               
//                                                                         by ADS1115                                                       by ADS1115    
//                     :<------------------- Frame 3: Data Byte 1 ------------------->:<----------------- Frame 4: Data Byte 2 ------------------->:
//
// This diagram shows a complete write sequence. We start the transmission by pulling SDA low while SCL is high. We then send the address of the peripheral along with a zero for the R/W bit followed by an ACK from the ADC. 
// The next byte selects one of the 4 main registers again it is followed by an ACK. The final two bytes send the data, most significant bit and most significant byte first and each of the two bytes has its own ACK. Finally
// we send an end of transmission by pulling SDA high while SCL is high.
//
// The process for reading is as follows:
//
//                            #1                                              #9    #1                                              #9   
//  CLOCK (SCL) : '1' ----+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +-----                                                                                                                                                                                                 
//                        |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |   
//                        |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |      ...                                                                                                                                                                      
//                '0'     +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+                                                                                                                                                                                                   
//                                                                                                                                                                     
//                                                                                                                                                                        
//                                                                                                                                                                            
//  DATA (SDA) '1'  \        /--\              /--\        /--\  /--\                                                  /--\  /--\              /  "End"                                         
//                   \      /    \            /    \      /    \/    \    _                                           /    \/    \            /   by Master                                                                                                                                     
//                    \    /  '1' \ '0'  '0' / '1'  \ '0'/  A1 /\ A0  \ R/W      /\'0'   '0'   '0'   '0'   '0'   '0' /\ P1 /\ P0  \          /   ...                                                                                                                                                                                                                                                                     
//             '0'     \--/        \--------/        \--/-----/  \-----\--------/  \--------------------------------/  \--/  \-----\--------/                                                                                                                                                                                                                                                                                                                                                                 
//               "Start"                                                    "ACK"                                                  "ACK"                                                                                                                                                                                                                                                                                                                                                      
//               by Master                                                by ADS1115                                            by ADS1115    
//                     :<-------------- Frame 1: Slave Address byte -------------->:<----------- Frame 2: Address Pointer Register ------------->:
// 
//
//                            #1                                              #9    #1                                              #9    #1                                              #9   
//  CLOCK (SCL) : '1' ----+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +-----                                                                                                                                                                                                 
//  (Continued)           |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |   
//                 ...    |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |      ...                                                                                                                                                                      
//                '0'     +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+                                                                                                                                                                                                   
//                                                                                                                                                                     
//                                                                                                                                                                        
//                                                                                                                                                                            
//  DATA (SDA) '1'  \        /--\              /--\        /--\  /--\  /--\        /--\  /--\  /--\  /--\  /--\  /--\  /--\  /--\        /--\  /--\  /--\  /--\  /--\  /--\  /--\  /--\              /  "End"                                         
//  (Continued)      \      /    \            /    \      /    \/    \/  _ \      /    \/    \/    \/    \/    \/    \/    \/    \      /    \/    \/    \/    \/    \/    \/    \/    \            /   by Master                                                                                                                                     
//                    \    / '1'  \ '0'  '0' / '1'  \ '0'/  A1 /\ A0 / R/W  \    /\D15 /\D14 /\D13 /\D12 /\D11 /\D10 /\ D9 /\ D8 /\    /\ D7 /\ D6 /\ D5 /\ D4 /\ D3 /\ D2 /\ D1 /\ D0  \          /   ...                                                                                                                                                                                                                                                                     
//             '0'     \--/        \--------/        \--/-----/  \--/--------\--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \-----\--------/                                                                                                                                                                                                                                                                                                                                                                 
//               "Start"                                                    "ACK"                                                  "ACK"                                                 "ACK"                                                                                                                                                                                                                                                                                                                                                                     
//               by Master                                                by ADS1115                                            by Master                                               by Master                   
//                     :<-------------- Frame 3: Slave Address byte -------------->:<------- Frame 4: Data Byte 1 Read Register -------->:<---------- Frame 5: Data Byte 2 Read Register --------------->:
//
//
// The first two bytes are like above, because they are essentially a write command without data to select the correct register, you can see after these first to bytes there is an end of transmission (Stop signal) separating it from
// the read. Once the register is selected we issue a new I2C command with a new start of transmission, this time with a one for the R/W bit to signify we want to read data, followed by us clocking two bytes worth of clock signals 
// (plus ACK bits) to receive the full 16 bits of the selected register.
// 
// Now these two flows are just how to write and read registers, in-order to perform a full conversion we will need to read and write multiple registers. The entire flow is:
// 1. Write to config register to setup general configuration and start conversion.
// 2. Read config register until you see the conversion is complete.
// 3. Read conversion register.
//
// Creating a state machine for this whole process where you directly control 'SDA' and 'SCL' would result in a very large and complex state machine. Even within a single sub-task, for example reading a register, we have 5 bytes, some of 
// which we are sending, some we are receiving, We need to send a start and stop event in the middle unlike with the write command here we don't want to continue writing data, etc.. It's not that it can't be done, it's just like the 
// example of drawing a circuit diagram with only transistors it can be done, but is unnecessarily complex.
//
// Let's us try and break up the two commands we saw above into reusable components.
//
//
// < Sub Tasks >
// 
// Now there are multiple ways of splitting a large process into sub-tasks, and multiple layers of granularity that you can use. One method is to look for repetition, if we take a look at our end process, we need to write to 1 register
// and read from two others.
// If we had a sub-task for read register and write register we could compose our main conversion flow pretty easily. The problem with this idea is like mentioned each of these tasks on their own is already pretty large. So let's go down
// a level and take a look if we can split the read / write register commands themselves into smaller composable parts.
//
// For example let's break up the two flows into the following sub-tasks
// 1. Start a TX
// 2. Stop a TX
// 3. Read a byte + send ack
// 4. Write a byte + receive ack
//
// Looking at the write register example with this split:
//
//
// The process split for writing is as follows:
//                                                                                      
//             START TX                      SEND BYTE + GET ACK                               SEND BYTE + GET ACK   
//        ................... ......................................................  ......................................................                                            
//                          . .                                                    .  .                                                    .   
//                          . .                                                    .  .                                                    .                                          
//                          . .                                                    .  .                                                    .    
//                          . . #1                                              #9 .  . #1                                              #9 .  
//  CLOCK (SCL) : '1' ----+ . .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+.  .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+.                                                                                                                                                                                                     
//                        | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.    
//                        | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.    ...                                                                                                                                                                      
//                '0'     +-.-.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +.--.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +.--                                                                                                                                                                                                  
//                          . .                                                    .  .                                                    .                                
//                          . .                                                    .  .                                                    .                                   
//                          . .                                                    .  .                                                    .                                       
//  DATA (SDA) '1'  \       . ./--\              /--\        /--\  /--\            .  .                                    /--\  /--\      .  /                                              
//                   \      ./.    \            /    \      /    \/    \    _      .  .                                   /    \/    \     . /                                                                                                                                               
//                    \    /. . '1' \ '0'  '0' / '1'  \ '0'/  A1 /\ A0  \ R/W      ./\.'0'   '0'   '0'   '0'   '0'   '0' /\ P1 /\ P0  \    ./   ...                                                                                                                                                                                                                                                                     
//             '0'     \--/ . .      \--------/        \--/-----/  \-----\--------/.  .\--------------------------------/  \--/  \-----\--/.                                                                                                                                                                                                                                                                                                                                                                 
//               "Start"    . .                                               "ACK".  .                                               "ACK".                                                                                                                                                                                                                                                                                                                                                      
//               by Master  . .                                          by ADS1115.  .                                          by ADS1115.    
//                     :<---.-.---------- Frame 1: Slave Address byte -------------.->.:<--------- Frame 2: Address Pointer Register ------.---->:
//                          . .                                                    .  .                                                    . 
//         .................. ......................................................  ......................................................
//                                                                                                                                                                     
//                                          SEND BYTE + GET ACK                                                SEND BYTE + GET ACK                            END TX                                                          
//                           ......................................................             .......................................................  .................                                                                                                              
//                           .                                                    .             .                                                     .  .                                                                                                                                                                                                              
//                           . #1                                              #9 .             .  #1                                              #9 .  .
//  CLOCK (SCL) : '1'        .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+.             . +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+.  .+-----                                                                                                                                                                                                  
//  (Continued)              .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.             . |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|   
//                   ...     .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.             . |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|                                                                                                                                                                         
//                '0'  ------.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +.-------------.-+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +.--.+                                                                                                                                                                                                   
//                           .                                                    .             .                                                     .  .                             
//                           .                                                    .             .                                                     .  .                                
//                           .                                                    .             .                                                     .  .                  
//  DATA (SDA) '1'           ./--\  /--\  /--\  /--\  /--\  /--\  /--\  /--\      .        /--+-.----\  /--\  /--\  /--\  /--\  /--\  /--\  /--\      .  .      /                                                                   
// (Continued)              /.    \/    \/    \/    \/    \/    \/    \/    \     .       /    \.     \/    \/    \/    \/    \/    \/    \/    \     .  .     /
//                   ...    \.D15 /\D14 /\D13 /\D12 /\D11 /\D10 /\ D9 /\ D8  \    .      /      .\ D7 /\ D6 /\ D5 /\ D4 /\ D3 /\ D2 /\ D1 /\ D0 /\    .  .    /                                                                                                                                                                                                                                                                             
//             '0'           .\--/  \--/  \--/  \--/  \--/  \--/  \--/  \-----\---.-----/       . \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \---.--.---/   "End"                                                                                                                                                                                                                                                                                                                                                                                       
//                           .                                                "ACK."            .                                                "ACK".  .     by Master                                                                                                                                                                                                                                                                                                                                               
//                           .                                              by ADS.1115         .                                         by ADS1115  .  .
//                     :<----.--------------- Frame 3: Data Byte 1 ---------------.---->:<------.----------- Frame 4: Data Byte 2 ------------------->:  .
//                           .                                                    .             .                                                     .  .
//                           ......................................................             .......................................................  .................
//
// We can see it can easily be defined as 6 sub-commands:
// 1. Start TX
// 2. Send (Address + R/W) then get Ack
// 3. Send Register index then get ack
// 4. Send top byte then get ack
// 5. Send bottom byte then get ack
// 6. End TX
//
//
// If sub-tasks were functions in a higher level programming language we would have something like the following:
// start_i2c()
// send_byte((address << 1) + readWriteBit)
// send_byte(registerIndex)
// send_byte(topByte)
// send_byte(bottomByte)
// stop_i2c()
//
//
// And if we take a look at reading a register we have something like the following:
//
//             START TX                      SEND BYTE + GET ACK                               SEND BYTE + GET ACK                                 END TX      
//        ................... ......................................................  ......................................................  .................
//                          . .                                                    .  .                                                    .  .
//                          . . #1                                              #9 .  . #1                                              #9 .  .
//  CLOCK (SCL) : '1' ----+ . .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+.  .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+.  .+-----                                                                                                                                                                                                 
//                        | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|   
//                        | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|      ...                                                                                                                                                                      
//                '0'     +-.-.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +.--.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +.--.+                                                                                                                                                                                                   
//                          . .                                                    .  .                                                    .  .                              
//                          . .                                                    .  .                                                    .  .                                 
//                          . .                                                    .  .                                                    .  .                                     
//  DATA (SDA) '1'  \       . ./--\              /--\        /--\  /--\            .  .                                    /--\  /--\      .  .      /  "End"                                         
//                   \      ./.    \            /    \      /    \/    \    _      .  .                                   /    \/    \     .  .     /   by Master                                                                                                                                     
//                    \    /. . '1' \ '0'  '0' / '1'  \ '0'/  A1 /\ A0  \ R/W      ./\.'0'   '0'   '0'   '0'   '0'   '0' /\ P1 /\ P0  \    .  .    /   ...                                                                                                                                                                                                                                                                     
//             '0'     \--/ . .      \--------/        \--/-----/  \-----\--------/.  .\--------------------------------/  \--/  \-----\---.--.---/                                                                                                                                                                                                                                                                                                                                                                 
//               "Start"    . .                                              "ACK" .  .                                               "ACK".  .                                                                                                                                                                                                                                                                                                                                                    
//               by Master  . .                                         by ADS1115 .  .                                          by ADS1115.  .  
//                     :<---.-.---------- Frame 1: Slave Address byte -------------.->:<----------- Frame 2: Address Pointer Register -----.--.------>:
//                          . .                                                    .  .                                                    .  .
//           ................ ......................................................  ....................................................... .................
//
//            START TX                       SEND BYTE + GET ACK                                       READ BYTE + SET ACK                                      READ BYTE + SET ACK                         END TX      
//       .................... ......................................................  ....................................................... ....................................................... .................
//                          . .                                                    .  .                                                     . .                                                     . .
//                          . . #1                                              #9 .  . #1                                              #9  . . #1                                              #9  . .
//  CLOCK (SCL) : '1' ----+ . .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+.  .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+ . .+--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+ . .+-----                                                                                                                                                                                                 
//  (Continued)           | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | . .|   
//                 ...    | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |.  .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | . .|  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | . .|      ...                                                                                                                                                                      
//                '0'     +-.-.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +.--.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +-.-.+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +--+  +-.-.+                                                                                                                                                                                                   
//                          . .                                                    .  .                                                     . .                                                     . .
//                          . .                                                    .  .                                                     . .                                                     . .
//                          . .                                                    .  .                                                     . .                                                     . .
//  DATA (SDA) '1'  \       . ./--\              /--\        /--\  /--\  /--\      .  ./--\  /--\  /--\  /--\  /--\  /--\  /--\  /--\       . ./--\  /--\  /--\  /--\  /--\  /--\  /--\  /--\       . .      /  "End"                                         
//  (Continued)      \      ./.    \            /    \      /    \/    \/  _ \     . /.    \/    \/    \/    \/    \/    \/    \/    \      ./.    \/    \/    \/    \/    \/    \/    \/    \      . .     /   by Master                                                                                                                                     
//                    \    /. .'1'  \ '0'  '0' / '1'  \ '0'/  A1 /\ A0 / R/W  \    ./\.D15 /\D14 /\D13 /\D12 /\D11 /\D10 /\ D9 /\ D8 /\    /.\. D7 /\ D6 /\ D5 /\ D4 /\ D3 /\ D2 /\ D1 /\ D0  \     . .    /   ...                                                                                                                                                                                                                                                                     
//             '0'     \--/ . .      \--------/        \--/-----/  \--/--------\--/.  .\--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/  \--/ . .\--/  \--/  \--/  \--/  \--/  \--/  \--/  \-----\----.-.---/                                                                                                                                                                                                                                                                                                                                                                 
//               "Start"    . .                                              "ACK" .  .                                              "ACK"  . .                                              "ACK"  . .                                                                                                                                                                                                                                                                                                                                                                  
//               by Master  . .                                         by ADS1115 .  .                                         by Master   . .                                           by Master . .                 
//                     :<---.-.---------- Frame 3: Slave Address byte -------------.->:<------- Frame 4: Data Byte 1 Read Register -------->:<.---------- Frame 5: Data Byte 2 Read Register -------.-.------->:
//                          . .                                                    .  .                                                     . .                                                     . .
//      ..................... ......................................................  ....................................................... ....................................................... ..................
//
//
// Here we can first of all split this into two main tasks:
// 1.Point to the correct register
// 2.Read the register
//
// And each of these tasks can be split into our 4 sub-tasks like with the write example. Using this split, we have a very manageable sub-task layer with only 4 operations each of which being pretty straightforward to implement as
// they are limited to a single byte and then we can easily compose them into each of the operations we need to perform a conversion.
//
// Let us restate the conversion process now from start to finish using our 4 components
// Task 0 Setup Conversion
//  - 0 start_i2c()
//  - 1 send_byte({address, w})
//  - 2 send_byte(select_config_register)
//  - 3 send_byte(config_with_channel_upper)
//  - 4 send_byte(config_with_channel_lower)
//  - 5 stop_i2c()
//
// Task 1 Check if Ready
//  - 0 wait x amount of time
//  - 1 start_i2c()
//  - 2 send_byte({address, r})
//  - 3 read_byte() // reading config upper byte
//  - 4 store 1st byte + read_byte() // reading config lower byte
//  - 5 stop_i2c()
//
// Task 2 Switch Back to Conversion Register
//  - 0 delay some time
//  - 1 start_i2c()
//  - 2 write_byte({address, w})
//  - 3 write_byte(select_conversion_register)
//  - 4 stop_i2c()
//
// Task 3 Read Value
//  - 0 start_i2c()
//  - 1 write_byte({address, r})
//  - 2 read_byte() // reading conversion register upper
//  - 3 store 1st byte + read_byte() // reading conversion register lower
//  - 4 store 2nd read byte
//  - 5 stop_i2c()
//
//
// By abstracting the physical I2C stuff into its own layer we are able to easily copy the diagrams from the ADC datasheet we color coded in-order to represent the full flow.
// This change lowered the total states required to 19, but we can do even better. Taking a look at the states listed above we can see multiple duplicates for example:
// Task 0 - Subtask 0
// Task 1 - Subtask 1
// Task 2 - Subtask 1
// Task 3 - Subtask 0
//
//
// Are all 'start_i2c' and we also have 4 'stop_i2c' steps, reading bytes is also the same for both tasks 1 and 3, etc.. Going through the list we can narrow down the number of unique states we need to create using our building blocks
// to only 11. This means we can create these 11 micro procedures along with the 4 sub-tasks we used as our building block for a total of 15 states.
//
// So with a plan of attack, let's get into the implementation.
module top
#(
  /* Tang Nano 9K Board - featuring GOWIN FPGA: GW1NR-LV9 QFN88P (rev.C) */
  parameter EXT_CLK_FREQ = 27000000, // external clock source, frequency in [Hz], 
  parameter EXT_CLK_PERIOD = 37.037, // external clock source, period in [ns], 
  parameter STARTUP_WAIT_MS = 10 // make startup delay of 10 [ms] for our LCD screen
)
(
  input wire EXT_CLK,  // This is the external clock source on the board - expected 27 [MHz] oscillator. 
  input wire BTN_S1, // This pin is tied to a button 'S1' on the board, and will be used as a 'reset' source (active-low) 
  input wire BTN_S2, // This pin is tied to a button 'S2' on the board, and will be used as a general user input source (active-low) 
  output reg [5:0] LED_O={6{1'b1}}, // 6 Orange LEDs on the board, active-low , default to all high (leds are OFF)
  // LCD 0.96" (128x64 pixels) SPI interface - SSD1306 controller
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
  output wire FLASH_SPI_CLK,  //  clock signal for flash memory

  inout wire ADC_I2C_SDA, // bi-directional pin for the ADS1115 I2C SDA signal
  output reg ADC_I2C_SCL, // just output pin for the ADS1115 I2C SCL signal, no need for tri-state (we don't need to support clock-stretching in our case)
  output reg ADC_I2C_ADDR = 1, // Make (fix) the I2C ADDR pin - high. Next we need to connect the ADDR pin on the ADS1115 board to 3.3v as-well in-order to set the I2C address to 7'b1001001.
  input wire ADC_ALERT
);
localparam STARTUP_WAIT_CYCL = ((EXT_CLK_FREQ/1000)*STARTUP_WAIT_MS);
// We can setup our screen and text engine modules as follows: LCD-Screen and Text-Engine related signals:
wire [9:0] pixelAddress;  // A value from 0 - 1023 , which disects the screen into addresses of pixel bytes
wire [7:0] textPixelData; // pixel byte data - a vertical column of 8-pixel bits
wire [5:0] charAddress;   // A value from 0 - 63
reg  [7:0] charOutput = " ";    // A printable ASCII character - init <empty> char
// the screen iterates over all pixels on screen in 1024 bytes. Each time it requests a single byte using the 'pixelAddress' register ...
screen #(STARTUP_WAIT_CYCL) scr ( // Hook up our screen module.
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

// This is accomplished by using tristate logic and the special inout keyword to signify the wire can be used as both an input and an output. FPGAs have limited support for tristate logic but the IO pins have their own tri-state registers, 
// because of this we will separate our module from the tristate logic giving the pnr the flexibility to place each where it fits best. So in our module we use two separate wires for each direction and an extra wire to say which if we are
// currently inputting data or outputting.
// Basically in the top module we can do something like the following to control the tristate io pin:
// module top(
//  inout i2cSDA
// );
//     assign i2cSDA = isSending ? sdaOutReg : 1'bz;
// endmodule
//
// So if we are sending data and the bit we want to send is '0', then we pull the line low, if we are sending a '1' or inputting data we stop driving the line and rely on the external pullup to set the line high, but we will get to this 
// code when we write the top module. It is also worth noting that in the constraints file you can theoretically set the pin mode to open drain which will handle this automatically.
// Back to our i2c module's inputs, we next have an output wire for SCL here we are not using a tristate buffer and simply an output wire since we don't need to support clock-stretching in our use-case.
// To control the tristate io pin:
// assign ADC_I2C_SDA = isSending ? sdaOut : 1'bz;
// So if we are currently sending over the SDA line then connect the pin to the output register for SDA otherwise if we are currently reading, then sets the wire to high-impedance state (using the special
// 'z' bit literal) which means no value is driven on the line and we will be able to read the outside value making it an input.
// It's worth noting that I2C uses an open-drain configuration, which means the line itself is pulled high externally through a pull-up resistor and each side can only pull the line low. The main difference between this configuration and
// a standard configuration (like in the code example above) is that in an open-drain configuration if either side pulls the line low, the line is definitely low and in a standard situation if one side pulls the line low and the either side
// high the line will be high. This ability for either side to force the line low allows for clock stretching, making the receiver of data "pause" the transmission if it needs more time to process something.
// The implementation for an open-drain style connection we change the assign to something like the following:
//
//   assign ADC_I2C_SDA = (isSending & ~sdaOut) ? 1'b0 : 1'bz;
//
// So if we are sending data and the bit we want to send is '0', then we pull the line low, if we are sending a '1' or inputting data we stop driving the line and rely on the external pullup to set the line high, but we will get to this 
// code when we write the top module.
// It is also worth noting that in the constraints file you can theoretically set the pin mode to open drain which will handle this automatically.

// Next we can instantiate our 'i2c' and 'adc' modules, this is pretty much exactly like how we did it in the testbench:
wire [1:0] i2cInstruction;
wire [7:0] i2cByteToSend; 
wire [7:0] i2cByteReceived; 
wire i2cComplete; 
wire i2cEnable;

wire sdaIn;
wire sdaOut;
wire isSending;
assign ADC_I2C_SDA = (isSending & ~sdaOut) ? 1'b0 : 1'bz;
assign sdaIn = ADC_I2C_SDA ? 1'b1 : 1'b0;

i2c c(
  .clk(EXT_CLK),
  .sdaIn(sdaIn), 
  .sdaOut(sdaOut),
  .isSending(isSending),
  .scl(ADC_I2C_SCL),
  .instruction(i2cInstruction),   
  .enable(i2cEnable),
  .byteToSend(i2cByteToSend), 
  .byteReceived(i2cByteReceived), 
  .complete(i2cComplete)
);

// Next we just need a few more registers for adding our ADC module:
reg [1:0] adcChannel = 0;
wire [15:0] adcOutputData;
wire adcDataReady;
reg adcEnable = 0;

adc #(7'b1001001) a( // We will hard-code the channel to channel 0 and set enable high so it will start a conversion. Other then that two wires that are required by our adc module.
  .clk(EXT_CLK), 
  .channel(adcChannel),  
  .outputData(adcOutputData),
  .dataReady(adcDataReady), 
  .enable(adcEnable), 
  .instructionI2C(i2cInstruction),
  .enableI2C(i2cEnable),
  .byteToSendI2C(i2cByteToSend),
  .byteReceivedI2C(i2cByteReceived),
  .completeI2C(i2cComplete)
);

// Next we have what will drive the adc module, like mentioned we want to have both the raw value and the value in volts so we can create registers for that:
reg [15:0] adcOutputBufferCh1 = 0;
reg [15:0] adcOutputBufferCh2 = 0;
reg [11:0] voltageCh1 = 0;
reg [11:0] voltageCh2 = 0;

localparam STATE_TRIGGER_CONV = 0;
localparam STATE_WAIT_FOR_START = 1; 
localparam STATE_SAVE_VALUE_WHEN_READY = 2;

reg [2:0] drawState = 0;

// After the registers which will hold the raw 16-bit value for each channel and registers to store the voltage level we have some states for a state machine:
always_ff @(posedge EXT_CLK) begin 
  case (drawState)
    STATE_TRIGGER_CONV: begin 
      adcEnable <= 1;
      drawState <= STATE_WAIT_FOR_START;
    end
    STATE_WAIT_FOR_START : begin 
      if(~adcDataReady) begin 
        drawState <= STATE_SAVE_VALUE_WHEN_READY;
      end
    end
    STATE_SAVE_VALUE_WHEN_READY: begin 
      if(adcDataReady) begin 
        adcChannel <= adcChannel[0] ? 2'b00 : 2'b01;
        if(~adcChannel[0]) begin 
          adcOutputBufferCh1 <= adcOutputData;
          voltageCh1 <= adcOutputData[15] ? 12'd0 : adcOutputData[14:3];
        end else begin 
          adcOutputBufferCh2 <= adcOutputData;
          voltageCh2 <= adcOutputData[15] ? 12'd0 : adcOutputData[14:3];
        end
        drawState <= STATE_TRIGGER_CONV;
        adcEnable <= 0;
      end
    end
  endcase 
end
// The first state triggers a conversion by setting the 'adcEnable' flag high, then we wait for the adc to be busy as to make sure we don't read the 'adcDataReady' high value from the 
// previous conversion.
// In the last step we wait for the ADC module to finish and return the raw conversion value, and then depending on which channel we were currently doing we store the raw value and
// the value in volts in their respective registers.
// Once we store a value we immediately start a new conversion this time on the other channel.
//
// But let's take another look at the code which sets the voltage:
// 
//   voltageCh1 <= adcOutputData[15] ? 12'd0 : adcOutputData[14:3];
//
// The number we receive is a signed 16-bit number and we are not using negative voltages so we basically have an unsigned 15-bit number. Because of small fluctuations in the conversion 
// even though we are only using the positive side we sometimes may get a negative number close to zero instead of zero. To fix this we can just check if the 16th-bit is high (in which case
// the signed number is negative) and we will just set the value to zero.
//
// The other interesting thing here is to convert the number from the equation we saw in the ADS1115 datasheet to decimal volts we simply take bit 4 to bit 15. From the datasheet we know 
// the equation to convert values for positive voltages is:
//
//         15-bit Value
//   FS * --------------
//            2^(15)
//
// And we set our FS value to 4.096 volts in the config register. The reason this number is so specific and not just 4 volts is because if we multiply the number by 1000 we get a power of two,
// 212 to be exact. So if we are multiplying by 212 and dividing by 215 then we are left with only a division of 2(15-12) = 23. Dividing by a power of two is simply removing the same amount of 
// lower bits so in our case we simply remove the last 3 bits and take bits 4 to 15 as our voltage and because we multiplied our voltage by 1000 we will have exactly 3 decimal points.
//
// This shouldn't be confused with floating point numbers which are stored completely separately, here we are dealing with fixed point numbers, which is where you are working with integers, but 
// you multiply the number by some factor so you have a fixed number of decimal places.
//
// Again this only works because we multiplied by 1000 to get a power of 2, if we would have only wanted 2 decimal places and only wanted to multiply by 100, then 409 is not a power of 2 and we
// would need to perform the actual math equation of multiplying the 15-bit value by 409 and then dividing by 215 (or removing the lower 15 bits after the multiplication).

// < Displaying the Results >
// Now that we are constantly retrieving conversion values for both channels the last thing we need to do is display the results on screen.
// 
// For converting the binary numbers into hex and decimal ASCII representations we will be using our modules toHex and toDec. We can start with the hex characters:
genvar i;
generate 
  for(i = 0; i < 4; i = i + 1) begin: hexValCh1
    wire [7:0] hexChar;
    toHex converter(EXT_CLK, adcOutputBufferCh1[{i,2'b0}+:4], hexChar);
  end
endgenerate
generate 
  for(i = 0; i < 4; i = i + 1) begin: hexValCh2
    wire [7:0] hexChar;
    toHex converter(EXT_CLK, adcOutputBufferCh2[{i,2'b0}+:4], hexChar);
  end
endgenerate
// We have a generate block to generate the verilog for 4 hex characters per channel. We have a 16-bit value and each hex character is 4-bits which is why we need 4 characters. The code is simply
// duplicated once for each channel.
//
// Next a very similar story to convert the voltage into decimal ASCII representation:
wire [7:0] thousandsCh1, hundredsCh1, tensCh1, unitsCh1;
wire [7:0] thousandsCh2, hundredsCh2, tensCh2, unitsCh2;

toDec dec1(
  EXT_CLK,
  voltageCh1,
  thousandsCh1,
  hundredsCh1,
  tensCh1,
  unitsCh1
);

toDec dec2(
  EXT_CLK,
  voltageCh2,
  thousandsCh2,
  hundredsCh2,
  tensCh2,
  unitsCh2
);

// Last but not least we will have an always block which will look at which character is being requested by the text engine based on the screen position being updated and we will place the correct 
// character to display into charOutput.
wire [1:0] rowNumber;
assign rowNumber = charAddress[5:4];

always_ff @(posedge EXT_CLK) begin 
  if(rowNumber == 2'd0) begin 
    case(charAddress[3:0])
      0:  charOutput <= "C";
      1:  charOutput <= "h";
      2:  charOutput <= "1";
      4:  charOutput <= "r";
      5:  charOutput <= "a";
      6:  charOutput <= "w";
      8:  charOutput <= "0";
      9:  charOutput <= "x";
      10: charOutput <= hexValCh1[3].hexChar;
      11: charOutput <= hexValCh1[2].hexChar;
      12: charOutput <= hexValCh1[1].hexChar;
      13: charOutput <= hexValCh1[0].hexChar;
      default: charOutput <= " ";
    endcase
  end else if(rowNumber == 2'd1) begin 
    case(charAddress[3:0])
      0:  charOutput <= "C";
      1:  charOutput <= "h";
      2:  charOutput <= "1";
      4:  charOutput <= thousandsCh1;
      5:  charOutput <= ".";
      6:  charOutput <= hundredsCh1;
      7:  charOutput <= tensCh1;
      8:  charOutput <= unitsCh1;
      10: charOutput <= "V";
      11: charOutput <= "o";
      12: charOutput <= "l";
      13: charOutput <= "t";
      14: charOutput <= "s";
      default: charOutput <= " ";
    endcase
  end else if(rowNumber == 2'd2) begin 
    case(charAddress[3:0])
      0:  charOutput <= "C";
      1:  charOutput <= "h";
      2:  charOutput <= "2";
      4:  charOutput <= "r";
      5:  charOutput <= "a";
      6:  charOutput <= "w";
      8:  charOutput <= "0";
      9:  charOutput <= "x";
      10: charOutput <= hexValCh2[3].hexChar;
      11: charOutput <= hexValCh2[2].hexChar;
      12: charOutput <= hexValCh2[1].hexChar;
      13: charOutput <= hexValCh2[0].hexChar;
      default: charOutput <= " ";
    endcase
  end else if(rowNumber == 2'd3) begin 
    case(charAddress[3:0])
      0:  charOutput <= "C";
      1:  charOutput <= "h";
      2:  charOutput <= "2";
      4:  charOutput <= thousandsCh2;
      5:  charOutput <= ".";
      6:  charOutput <= hundredsCh2;
      7:  charOutput <= tensCh2;
      8:  charOutput <= unitsCh2;
      10: charOutput <= "V";
      11: charOutput <= "o";
      12: charOutput <= "l";
      13: charOutput <= "t";
      14: charOutput <= "s";
      default: charOutput <= " ";
    endcase
  end
end
// We handle each row separately, for each row we have a case statement where we choose the correct character to display based on the current column.
endmodule


// Convert Binary number to Hex representation
module toHex(
  input wire clk,
  input wire [3:0] value, // we receive the 4-bit number which ...
  output reg[7:0] hexChar = "0" // ... we need to convert to an ASCII letter.
);

always_ff @(posedge clk) begin 
  hexChar <= (value <= 9) ? "0" + value : "A" + (value-10);
end
endmodule // toHex 

// Convert Binary number to Decimal representation - Double Dabble method
module toDec( // We receive as input: 
  input wire clk, // the clock and ...
  input wire [11:0] value, // ... the (binary) value we want to convert. then we output ... (ADS1115 ADC value)
  output reg [7:0] thousands = " ", // ... 4 ASCII characters 1 for each digit.
  output reg [7:0] hundreds = " ", 
  output reg [7:0] tens = " ",
  output reg [7:0] units = "0"
);

reg [15:0] digits = 0; // a register for the digits which like we saw above we need 4 per digit so here we have 16 bits, we will be shifting the value into here.
reg [11:0] cachedValue = 0; // a register to cache the value. This conversion process happens over multiple clock cycles so we don't want the number we are converting to change in the middle,
reg  [3:0] stepCounter = 0; // a register to store which shift iteration we are, because our input value is 12 bits wide, we need to perform the add3 + shift steps 11 times to convert the full number,
reg  [3:0] state = 0; // a register  to hold our current state in the conversion state machine.

localparam START_STATE = 0; // Starting state - here we need to cache value & reset registers
localparam ADD3_STATE = 1; // Add 3 - here we check if any of the 4 digits in the 16 bits need us to increment them by 3. 
localparam SHIFT_STATE = 2; // Shift - here we shift the cached value into the digits register.
localparam DONE_STATE = 3; // Done - here we store the results in our output buffers in ascii format.

always_ff @(posedge clk) begin 
  case(state)
    START_STATE: begin 
      cachedValue <= value; // store 'value' to 'cachedValue' to lock it for the rest of the calculation.
      stepCounter <= 0; // initializes the counter and ... 
      digits <= 0; // ... digits register to 0
      state <= ADD3_STATE; //  From here we go to ADD3_STATE (we could have skipped it since on the first iteration none of the digits require adding 3, but to keep the order I go there next).
    end 
    ADD3_STATE: begin  // In this state we check for each of the 4 digits if they are over 5, if so we add 3 to that digit.
      digits <= digits +
                ((digits[3:0] >= 5)? (3 << 0) : 0) + // For the first digit the value is actually 3, ... 
                ((digits[7:4] >= 5)? (3 << 4) : 0 << 0) + // ... for the second digit we need to shift 3 four decimal places resulting in 48, ...
                ((digits[11:8] >= 5)? (3 << 8) : 0 << 0)+ // ... and shifting 48 another 4 decimal places gives us 768, ... 
                ((digits[15:12] >= 5)? (3 << 12) : 0 << 0); // ... and shifting 768 another 4 decimal places gives us 12228.
      state <= SHIFT_STATE;
    end 
    SHIFT_STATE: begin 
      digits <= {digits[14:0], cachedValue[11]}; // First, shift digits over by 1 to the left, losing bit 15, but inserting bit 11 of our cached value
      cachedValue <= {cachedValue[10:0],1'b0}; // We also then shift cachedValue to remove bit 11 since we already "dealt" with it.
      if(stepCounter == 11) // If stepCounter equals 11 it means we have already shifted all 12 times and we can move onto the done state, otherwise ... 
        state <= DONE_STATE;
      else begin  // ... we increment the counter and go back to the add 3 state to continue the algorithm.
        state <= ADD3_STATE;
        stepCounter <= stepCounter + 1;
      end 
    end 
    DONE_STATE : begin
      thousands <= "0" + digits[15:12]; 
      hundreds <= "0" + digits[11:8];
      tens     <= "0" + digits [7:4];
      units    <= "0" + digits [3:0];
      state <= START_STATE; // ... then goes back to the first starting state to get the new updated value and start converting it.
    end 
  endcase
end
// The only difference here is that we added another digit extra so that we can display the voltage as 4 digits.
endmodule // toDec


// < Conclusion >
//
// In this article we explored the ADS1115 ADC, the I2C protocol and hopefully a more general approach that can be used to implement a new core. As a rule of thumb if something is complicated to 
// explain or implement then you are usually dealing with a compound task and breaking it up into sub tasks / building blocks can make it a lot simpler and easier.
