/*
Let's divide the screen into 4 rows of text this would mean that each character could be up to 16 pixels tall.
As for the width of each character we have a total of 128 pixels so if we make each character 8 bits wide we 
can store a maximum of 16 characters per row. We'll store the bytes in the memory array in hex format - 
to a file "font.hex", which will contain ASCII chars: 32d - 126d  - all the standard visible characters including space.

As we saw in the previous article in-order to fully update the screen we need to send it 1024 bytes, which means our pixel counter / address needs to be 10 bits long. 
For each of the values between 0-1023 we need to know how to decipher:
1. which text row we are on
2. which character in the row
3. which column of the character
4. if we are on the top half of the column or bottom half (again because each vertical column is 16 pixels or 2 bytes).

This can be accomplished using our mapping logic and a little understanding of binary.

Deciphering the Address
Before we start splitting characters into rows I think it is more convenient to think of all 4 rows as a single 64 character wide array. 
So for each OLED pixel address we need to think about which character out of the 64 possible character positions it belongs to.
Looking back at the order the OLED pixel counter updates:

We can see that we go left to right then drop down to the next row, each two rows is one character we know that the character index has to repeat the last 16 indices twice once for the top row and once for the bottom row.

The pattern for character index has to be like the following:

 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47,
48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63,
48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63

Where each number represents the value for 8 columns. The top row maps to the characters 0-15 then wraps around again to the same numbers to do the bottom row of those characters, then we continue counting the next 16.
To accomplish this we need a sub counter for the 8 columns, which once it completes it increments the character index, then after 16 times increments it repeats the same 16 only after which it continues to the next 16.
Because all the key numbers are powers of 2 we can simply use the bits of the address to accomplish this.

So, for a 10-bit (0-1023 bit) pixelCounter value, we can use the decoding :
bit9, bit8: Character Index (top bits)
bit7: Top Row Flag ('0' means its the top-row, '1' means its the bottom-row)
bit6, bit5, bit4, bit3:  Character Index (lower bits: 16) 
bit2, bit1, bit0: Column Index (this is the actual display column index - we have 8 columns per character)

In our case we want a cycle of 8 for the columns, then for that to repeat in a second cycle of 16, then we need for the entire 16x8 cycle to happen again but without changing the character index, 
so the next bit after the 16 cannot be connected to character index, and finally we want that hole cycle of 2x16x8 to happen 4 times.
So by dividing the bits as-per the repeat pattern, we let the natural bit overflow of counting handle everything for us.

Another way to think of it is that the lower 16 bits of character index are the character number in a row and the top two bits are the row number.

Implementing the Text Engine
Let's start by making some changes to the current screen module to make it receive the data from an outside module instead of from screenBuffer. To do this we will output from the module the pixel byte address and we will input the desired pixel data for that address:
*/
module textEngine(
  input wire clk,
  input [9:0] pixelAddress, // This is the address (index) of the a LCD byte segment (8-bit), that needs to be provided: (0 - 1023d)
  output [7:0] pixelData // This is the pixel (byte) that is to be output to the LCD
);
  
// Create a memory for our font where each index stores a single byte and we have 1520 bytes which is 16 bytes for each of the ASCII 95 characters - ASCII[32 : 126] , which all all the standard visible characters including space. 
// The next lines loads the font.hex file we generated at the beginning into this memory. 
// Note: The first byte ('fontBuffer[0]') - is the first column (of 8 per character) of the 'top' (8bit) part of the first included ASCII character (ASCII[32]), and, 
// the following byte ('fontBuffer[1]') is the the 'bottom' (8bit) part of the same column the character. Then ('fontBuffer[2]') is the top byte of the second column of the same ASCII character, and so on...  
reg [7:0] fontBuffer[1519:0];
initial $readmemh("font.hex",fontBuffer);

// Split up the address from a pixel index to the desired character index column and whether or not we are on the top row:
wire [5:0] charAddress;
wire [2:0] columnAddress;
wire topRow;
// Also need a buffer to store the output byte. 
reg [7:0] outputBuffer; 

// Connecting these up is simple now that we understand the mapping:
// The column address is the last 3 bits, the character address is made up of a lower 16 counter and the higher 4 counter for the rows. 
// For the flag which indicates whether we are on the top row or bottom row we can just take a look at bit number 8 where it will be 
// 0 if we are on the top row and 1 if it is the second iteration and we are on the bottom, so we invert it to match the flag name.
assign charAddress = {pixelAddress[9:8],pixelAddress[6:3]};
assign columnAddress = pixelAddress[2:0];
assign topRow = !pixelAddress[7]; // if we're on the top row (top 8-bit segment) of a charcter - 1'b1; 
// Attach the decoded/processed character (byte) from 'pixelAddress' 
assign pixelData = outputBuffer;

// Converting a Letter to Pixels
// With all the mapping out of the way let's take a look at how we now convert a letter to pixels.
// Let's take a look at how we would convert a letter using all the mapping data we just prepared.
// 'charOutput' will be the actual character we want to output, and 'chosenChar' will check if it is in range and if not replace 
// the character with a space (character code 32) so it will simply be blank:
wire [7:0] charOutput, chosenChar; // ASCII byte value 
assign chosenChar = ((charOutput >= 32) && (charOutput <= 126)) ? charOutput : 32; 

// Note:
// If we look back at how we stored our font data (font.hex) -  we stored the first column top byte then the first column second byte then the next column top byte and so on.
// So if we want the letter "A" in memory, we know that its ascii code is 65 and our memory starts from ascii code 32 subtracting them gives us the number of characters from
// the start of memory we need to skip which in this case is 33. We need to multiply this number by 16 as each character is 16 bytes long giving us 528 bytes. 
// Next if we wanted column index 3 we know each column is 2 bytes so we would need to skip another 6 bytes. Lastly once at the column boundary we know the first byte is for
// the top row and the second byte is for the bottom row of the character, so depending on which we need we optionally skip another byte.
// In code this looks something like the following:
// ((chosenChar - 8'd32) << 4) + (columnAddress << 1) + (topRow? 0 : 1)
// We take the character we want to display, subtract 32 to get the offset from start of memory. Multiply by 16 (by shifting left 4 times) to get the start of the character.
// Add to this the column address multiplied by 2 (again by shifting left by 1) and optionally adding another 1 if we are on the bottom row.
// This can be used to access the exact byte from the font memory needed:
always_ff @(posedge clk) begin 
  outputBuffer <= fontBuffer[((chosenChar - 8'd32) << 4) + (columnAddress << 1) + (topRow? 0 : 1)];
end
// With this one line we are mapping the desired character to the exact pixels for the specific column and row. 

// The only thing missing is to know which character to output, but for now if we just add:
// assign charOutput = "A"; // It should simply display the letter A for all character positions.

// We can now go back to our textEngine module and add the following instances of our text row:
wire [7:0] charOutput1, charOutput2, charOutput3, charOutput4;

textRow #(6'd0) t1(
  clk,
  charAddress,
  charOutput1
);

textRow #(6'd16) t2(
  clk,
  charAddress,
  charOutput2
);

textRow #(6'd32) t3(
  clk,
  charAddress,
  charOutput3
);

textRow #(6'd48) t4(
  clk,
  charAddress,
  charOutput4
);

// We create 4 instances each offset 16 from the previous and we pass each one it's own output line for the character it thinks should be on screen. We can then replace the old 
// assignment to charOutput with the following:
assign charOutput = (charAddress[5] && charAddress[4]) ? charOutput4 : ((charAddress[5]) ? charOutput3 : ((charAddress[4]) ? charOutput2 : charOutput1));
// Here we are multiplexing the 4 values and only looking at the value from the current row. We have already seen that the top two bits of the character address represent the row number.
// So if they equal 3 (row index 3 which means both bits are 1) then it is row 4, if the bits are 10 then it is row 3, 01 is row 2 and finally 00 is row 1.
endmodule

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
  input clk,
  input [7:0] readAddress, // it receives a character address (0-63) of the LCD and ...
  output[7:0] outChar  // ... will return an ASCII byte (reprsenting 1 character) for that character poistion
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