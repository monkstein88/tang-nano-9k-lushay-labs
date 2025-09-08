// The main difference is that here I added another file called rows.v  where we will put the modules for our 4 screen rows.

// Displaying Specific Characters
// We are on the home stretch, we can now display any of the 95 (visible) characters, we just need a way to store which character is in each character position.
// We could do this with a 64 byte memory one byte for each character on the screen, but for cases where you may want multiple modules updating the screen at the same time 
// it is sometimes better to have multiple smaller memories then one big one, allowing different parts of your project to work in parallel.
// So in our example let's create a module which will represent a single row of text and then we can just instantiate 4 of them to fill up the screen.
module textRow
#(
  parameter ADDRESS_OFFSET = 8'd0
)
(
  input wire clk,
  input wire [7:0] readAddress, // it receives a character address (0-63) of the LCD and ...
  output wire[7:0] outChar  // ... will return an ASCII byte (reprsenting 1 character) for that character poistion
);
// ... from the 16 bytes in the textBuffer for its row. We also have a parameter 'ADDRESS_OFFSET' which will allow us to offset the rows by 16 characters.
// So the first row will output character 0-15 from the buffer for character address 0-15, but the second row needs to output 0-15 while character index will be 
// 16-31 so we will send it 16 as the ADDRESS_OFFSET to subtract this difference.
reg [7:0] textBuffer[15:0];
assign outChar = textBuffer[(readAddress-ADDRESS_OFFSET)];

// Here initialize the memory manually, without using a file:
// This will loop through all 16 characters and set an initial value allowing for the toolchain to know what to preprogram into the memory created.
integer i;
initial begin 
//   for(i=0; i<16;i=i+1) begin 
//     textBuffer[i] = "0" + ADDRESS_OFFSET + i; // start from the ASCII value of "0"
//   end 
  for(i=0; i<16;i=i+1) begin 
    textBuffer[i] = 0; // clear it first,
  end
  // ... the memory with the message (chars) we want to see on the LCD.
  textBuffer[0] = "L";
  textBuffer[1] = "u";
  textBuffer[2] = "s";
  textBuffer[3] = "h";
  textBuffer[4] = "a";
  textBuffer[5] = "y";
  textBuffer[6] = " ";
  textBuffer[7] = "L";
  textBuffer[8] = "a";
  textBuffer[9] = "b";
  textBuffer[10] = "s"; 
  textBuffer[11] = "!"; 
end
endmodule


// The UART Row
// The first row we are going to implement is the UART row. This row will take each character coming in from the UART module and add it to a register. 
// We will store up to 16 characters as each row in our text engine can fit 16 characters. 
// We receive as inputs the clock - 'clk', whether or not the UART has a ready byte ('byteReady') that it read, that UART 'data' which is the character itself and
// the current character we want read 'outputCharIndex'. We also have one output which is supposed to be the character we want to display in ASCII format - 'outByte'.
module uartTextRow(
  input wire clk,
  input wire byteReady,
  input wire [7:0] data, 
  input wire [3:0] outputCharIndex,
  output wire [7:0] outByte
);

localparam BUFFER_WIDTH = 16; // 16 characters UART-RX buffer width

reg [7:0] textBuffer [0:(BUFFER_WIDTH-1)]; // a buffer to store our 16 ASCII (value) characters (each 8 bit)
reg [3:0] inputCharIndex = 0; // a register to store the (current) input character index. This register stores the column where we should put the next character that comes in. The first character goes in index zero then the next character goes to its right at index 1, etc.
reg [1:0] state = 0;  // a register to hold the current state as this module has multiple states. The reason for the multiple states is to sort of debounce the UART module. 

integer i;
initial begin 
  for(i=0;i<BUFFER_WIDTH;i++)
    textBuffer[i] = "\0"; // Initialize with zero (0d) value
end

localparam WAIT_FOR_NEXT_CHAR_STATE = 0;
localparam WAIT_FOR_TRANSFER_FINISH = 1;
localparam SAVING_CHARACTER_STATE = 2;

// Note: the UART module will set 'byteReady' high once it finishes receiving a character. it never clears this flag until the next character comes in. So if we were to add a character on every clock pulse where byteReady is high we would be adding the same character multiple times.
// In short: First we wait for byteReady to go low, then high and then we add the character to our textBuffer and increment the index.
always_ff @(posedge clk) begin  
  case(state)
    WAIT_FOR_NEXT_CHAR_STATE: begin // We can instead wait first for the byteReady flag to be set low which indicates a new character is being received ... 
      if(byteReady == 0)
        state <= WAIT_FOR_TRANSFER_FINISH;
    end
    WAIT_FOR_TRANSFER_FINISH: begin // ... Then in another state wait for byteReady to go back high, as we can't read the character until it is complete, ...
      if(byteReady == 1)
        state <= SAVING_CHARACTER_STATE;
    end 
    SAVING_CHARACTER_STATE: begin // ... and finally in the last state we can be sure that we have a character ready and that it is a new character that we haven't dealt with yet.
      // change the SAVING_CHARACTER_STATE to allow for backspace with minimal changes:
      if(data == 8'd8 || data == 8'd127) begin  // Check if the character from UART (data) equals the backspace or delete keys (8 or 127 in ascii) in which case ...  
        inputCharIndex <= inputCharIndex - 1; // ... we decrement the character index and ...
        if(inputCharIndex==0) // If we need to wrap around the display.
          textBuffer[BUFFER_WIDTH-1] <= 8'd32; // ... replace the previous character with a space (32 in ascii).
        else // If we don't need to wrap around
          textBuffer[inputCharIndex - 1] <= 8'd32; // ... replace the previous character with a space (32 in ascii).
      end else begin // Otherwise, like before  ... 
        inputCharIndex <= inputCharIndex + 1; // ... increment the character index ...  
        textBuffer[inputCharIndex] <= data; // ... and store the character as-is.
      end 
      state <= WAIT_FOR_NEXT_CHAR_STATE;
    end
  endcase 
end 

assign outByte = textBuffer[outputCharIndex]; // Since the data coming in is already ASCII data we don't need to convert anything and we assign 'outByte' to be the character from our character register at the current index.
endmodule // uartTextRow

// The Binary Row
// Our next row is another easy one, when displaying bits you only have two options to display a "1" or a "0". To display data in binary format you need 1 character for each bit and then depending on if the bit is 
// a 1 or 0 you choose the appropriate character. In our case we will be displaying an 8 bit value, so we receive as input, so we receive  as input parameters ...
module binaryRow(
  input wire clk, // ... the clock,
  input wire [7:0] value, // ... the value to display
  input wire [3:0] outputCharIndex, // ... and which of the 16 characters for this row is currently being requested.
  output wire [7:0] outByte // For output parameters we have a single parameter which is the ASCII character we want to display.
);

reg [7:0] outByteReg; // a register to store our output character which we assign to 'outByte' at the end of the module
wire [2:0] bitNumber; // a register used to index a bit of the ASCII character, which bit is to be displayed

assign bitNumber = outputCharIndex - 5; // because we want to write "Bin: " to the screen which is 5 characters, so when we are on character index 5, we want it to represent bit number 0.

always_ff @(posedge clk) begin 
  case (outputCharIndex)
    0: outByteReg <= "B";
    1: outByteReg <= "i";
    2: outByteReg <= "n";
    3: outByteReg <= ":";
    4: outByteReg <= " ";
    13, 14, 15: outByteReg <= " "; // we only need (the first) 13 characters (5 for text+8 bits) out of the 16 characters. The rest are blanks
    default: outByteReg <= (value[7-bitNumber]) ? "1" : "0"; // For the 8 bits where we are displaying the binary data we check the current bit if it is high we output a "1" in ascii and if not a "0". 
  endcase                                                    // Its worth noting we flip the direction (by doing 7-index) since when writing binary numbers it is common that the least significant bit is on the right hand side.
end

assign outByte = outByteReg;

endmodule // binaryRow

// The Hex / Decimal Row
// The next screen row module we want to implement is the row which will display the same counter value in hex and decimal representation.
// Hex is almost as easy as binary, since hex is base 16 which is also a power of 2 like binary, it means that every four bits translate to exactly one hex character. So to display our 8-bit number we need exactly 2 hex characters. 
// The conversion for each hex character is also pretty simple, with 4-bits we can have a maximum value of 15, for 0-9 we simply put that same digit as the output in ascii, and from 10-15 we move to letters A-F.
module toHex(
  input clk,
  input [3:0] value, // we receive the 4-bit number which ...
  output reg[7:0] hexChar = "0" // ... we need to convert to an ASCII letter.
);

always_ff @(posedge clk) begin 
  hexChar <= (value <= 9) ? "0" + value : ("A" - 10) + value;
end
endmodule // toHex 

// Converting Binary to Decimal
// There are multiple ways to do this conversion, but in this article we will be implementing an algorithm called "Double Dabble". The principle of the algorithm is to use the same hex conversion
// we did above by making our base-10 system function like base-16. This is possible because if you think about it, 0-9 in both systems work exactly the same, the problem is that base-10 needs 
// to reset after 9 back to 0 and add another digit (10) whereas base-16 will continue until passing 15 to do this.
// If we designate 4-bits for each digit and shifted in the binary value into the bits we created for the digits we would in-deed have each digit separated in base 16. Another thing to note is that 
// by shifting bits in we are essentially multiplying by 2 each time. So the trick is every time a base 10 number would move to the next digit (would be above 10) we add 6 to make the base16 digit
// also roll over and behave like the base 10 equivalent.
// So by adding 6 we convert:
// 10 -> 16 which in base 16 is 10
// 11 -> 17 which in base 16 us 11
// and so on, as you can see for numbers 10 and up, by adding six we convert it to the hex number with the same digits.
// In practice since each shift is multiplying by 2, then we can perform the addition before the shifting in which case we want to add 3 every time the value for a digit is equal to or greater
// than 5 (instead of adding 6 for values >= 10).

// The maximum value for an 8-bit value is 255 so we need three digits, and we are using 4 bits per digit because we are simulating base-16.
// Since our number is 8-bits we need to shift 8 times to get the full number into our digits register. At each of these 8 iterations we first check if any of the digits are over 5, if so we know 
// that after the next shift they will be over 10 and need to overflow so we add 3 to that sub digit, which will cause the hex digit to overflow after the shift.
// After adding any offsets required we shift the next bit in, and perform this for the number of bits in the original number. Once completed each 4-bit section will have the value for 1 of the 3 decimal 
// digits. To implement this we can create a module as follows:
module toDec( // We receive as input: 
  input wire clk, // the clock and ...
  input wire [7:0] value, // ... the (binary) value we want to convert. then we output ...
  output reg [7:0] hundreds = " ", // ... 3 ASCII characters 1 for each digit.
  output reg [7:0] tens = " ",
  output reg [7:0] units = "0"
);

reg [11:0] digits = 0; // a register for the digits which like we saw above we need 4 per digit so here we have 12 bits, we will be shifting the value into here.
reg  [7:0] cachedValue = 0; // a register to cache the value. This conversion process happens over multiple clock cycles so we don't want the number we are converting to change in the middle,
reg  [3:0] stepCounter = 0; // a register to store which shift iteration we are, because our input value is 8 bits wide, we need to perform the add3 + shift steps 8 times to convert the full number,
reg  [3:0] state = 0; // a register  to hold our current state in the conversion state machine.

localparam START_STATE = 0; // Starting state - here we need to cache value & reset registers
localparam ADD3_STATE = 1; // Add 3 - here we check if any of the 3 digits in the 12 bits need us to increment them by 3. 
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
    ADD3_STATE: begin  // In this state we check for each of the 3 digits if they are over 5, if so we add 3 to that digit.
      digits <= digits +
                ((digits [3:0] >= 5)? (3 << 0) : 0) + // For the first digit the value is actually 3, ... 
                ((digits [7:4] >= 5)? (3 << 4) : 0 << 0) + // ... for the second digit we need to shift 3 four decimal places resulting in 48, ...
                ((digits[11:8] >= 5)? (3 << 8) : 0 << 0); // ... and shifting 48 another 4 decimal places gives us 768.
      state <= SHIFT_STATE;
    end 
    SHIFT_STATE: begin 
      digits <= {digits[10:0], cachedValue[7]}; // First, shift digits over by 1 to the left, losing bit 11, but inserting bit 7 of our cached value
      cachedValue <= {cachedValue[6:0],1'b0}; // We also then shift cachedValue to remove bit 7 since we already "dealt" with it.
      if(stepCounter == 7) // If stepCounter equals 7 it means we have already shifted all 8 times and we can move onto the done state, otherwise ... 
        state <= DONE_STATE;
      else begin  // ... we increment the counter and go back to the add 3 state to continue the algorithm.
        state <= ADD3_STATE;
        stepCounter <= stepCounter + 1;
      end 
    end 
    DONE_STATE : begin 
      hundreds <= "0" + digits[11:8];
      tens     <= "0" + digits [7:4];
      units    <= "0" + digits [3:0];
      state <= START_STATE; // ... then goes back to the first starting state to get the new updated value and start converting it.
    end 
  endcase
end
endmodule // toDec


// Hex / Dec row :
module hexDecRow(
  input  wire        clk,
  input  wire  [7:0] value, // We receive the counter value ...
  input  wire  [3:0] outputCharIndex, // and based on the current character index ...
  output wire  [7:0] outByte // ... we need to output an ASCII character 
);

reg [7:0] outByteReg;

// HEX portion:
wire [3:0] hexLower, hexHigher;  //  creating wires to split the 8-bit byte value into two 4-bit value sections  and then ...
wire [7:0] lowerHexChar, higherHexChar; // use the module to convert those 4 bits values into individual ASCII value characters.

assign hexLower = value[3:0];
assign hexHigher = value [7:4];

toHex h1(clk, hexLower, lowerHexChar);
toHex h2(clk, hexHigher, higherHexChar);

// DEC portion:
wire [7:0] decChar1, decChar2, decChar3;
toDec dec(clk, value, decChar1, decChar2, decChar3);

// Final assignment: 
always_ff @(posedge clk) begin 
  case(outputCharIndex)
    0: outByteReg <= "H";
    1: outByteReg <= "e";
    2: outByteReg <= "x";
    3: outByteReg <= ":";
    5: outByteReg <= higherHexChar;
    6: outByteReg <= lowerHexChar;
    8: outByteReg <= "D";
    9: outByteReg <= "e";
    10: outByteReg <= "c";
    11: outByteReg <= ":";
    13: outByteReg <= decChar1; // Hundreds
    14: outByteReg <= decChar2; // Tens
    15: outByteReg <= decChar3; // Units
   default: outByteReg <= " ";
  endcase 
end 

assign outByte = outByteReg;
endmodule

// The Progress Bar Row
// This fourth (progress bar) row will show one way we can combine both text and direct pixel data onto the screen. For this row we will take the counter value and convert it to a progress bar representation.
// If our progress bar takes up the full screen width then it is 128 pixels wide, if the value we are trying to represent has 256 values then our progress resolution is 1 pixel width for each two values. So we
// can simply divide the value by two (shift off the LSB) and that would be the number of columns we are supposed to fill in our progress bar.
// A simple progress bar might look something like this:
module progressRow(
  input wire clk,
  input wire [7:0] value, // The byte value we want to depict under the form of a progress bar.
  input wire [9:0] pixelAddress, // This is the 8-bit pixel segment address, which covers the entire display - (0 to 1023)
  output wire [7:0] outByte 
);
  
reg [7:0] outByteReg; 
wire [6:0] column; // This is the column index part of the display


// This will work but it will make the progress bar simply be a rectangle 16 pixels tall, we can class it up a bit by shrinking the bar to not take up the full 16 pixels (top and bottor rows) and 
// by adding a border to our progress bar:
reg [7:0] bar, border; // add registers to store the pixel column for a filled column ('bar') and the pixel column for an empty column/border ('border'), ...
wire topRow; // ... we also need the topRow variable since we split our screen into 4 rows and there are 8 physical columns of pixels, we take up two physical rows.

assign topRow = !pixelAddress[7]; // This is the indicator bit, for either on top or bottom row. We can use this information to center the progress bar between the two rows. 
assign column = pixelAddress[6:0]; // take only the column part - of a 8-bit pixel segment address. (0 to 128)

always_ff @(posedge clk) begin 
  // For the top row we will output the top half of the progress bar and for the bottom row we will output the other half.
  if(topRow) begin 
    case(column)
      0, 127: begin  // right at the start and end of the bar.
        bar <= 8'b11000000;
        border <= 8'b11000000;
      end
      1, 126: begin  // right at the 2nd step after the start and 2nd step before end of the bar.
        bar <= 8'b11100000;
        border <= 8'b01100000;
      end 
      2, 125: begin  // right at the 3rd step after the start and 3rd step before end of the bar.
       bar <= 8'b11100000;
       border <= 8'b00110000;
      end 
      default: begin // - if we are in top row we set the bar to be 11110000 to light up the bottom 4 pixels of the column. Note: Both top and bottom will combine and altogether between the two rows we will have 8 pixels lit up.
       bar <= 8'b11110000;
       border <= 8'b00010000;       
      end
    endcase
  end else begin 
    case(column)
      0, 127: begin  // right at the start and end of the bar.
        bar <= 8'b00000011;
        border <= 8'b00000011;
      end
      1, 126: begin  // right at the 2nd step after the start and 2nd step before end of the bar.
        bar <= 8'b00000111;
        border <= 8'b00000110;
      end 
      2, 125: begin  // right at the 3rd step after the start and 3rd step before end of the bar.
        bar <= 8'b00000111;
        border <= 8'b00001100;
      end 
      default: begin // - if we are in the bottom row  we set bar to be 00001111 to light up the top 4 pixels. Note: Both top and bottom will combine and altogether between the two rows we will have 8 pixels lit up.
        bar <= 8'b00001111;
        border <= 8'b00001000;       
      end 
    endcase 
  end

  if(column > value[7:1]) // For each column index we check if it is bigger then the value divided by two (we do the division by just removing bit 0). 
    outByteReg <= border; // If the column index is bigger, then we don't want this column to be filled in so we output a column of zeros inside to make those pixels not light up and only the border lighted up...
  else 
    outByteReg <= bar; // ... otherwise, we output both the column and border filled up (lighted up)
end
assign outByte = outByteReg;

endmodule