// Preparing The Project
// For the text engine component we want to also expose the character address and chosen character, so that we can control them from the top module. The text engine should look like the following after those changes:
// It receives an ASCII character via 'charOutput' and converts it into 'pixelData' depending on the column / topRow etc. 
module textEngine(
  input  wire clk,
  input  wire [9:0] pixelAddress, // This is the address (index) of the a LCD byte segment (8-bit), that needs to be provided: (0 - 1023d)
  output wire [7:0] pixelData,    // This is the pixel (byte segment) that is to be output to the LCD
  output wire [5:0] charAddress,  // This is the decoded character address, which indicates "cursor" position across the LCD - given that we segmented in 16 chars x 4 rows = 64 addresses (values: 0-63)
  input  wire [7:0] charOutput    // This is be the actual character we want to display, we pass it to the module as ASCII (byte) value
);
  
// Create a memory for our font where each index stores a single byte and we have 1520 bytes which is 16 bytes for each of the ASCII 95 characters - ASCII[32 : 126] , which all all the standard visible characters including space. 
// The next lines loads the font.hex file we generated at the beginning into this memory. 
reg [7:0] fontBuffer[1519:0];             // Note: The first byte ('fontBuffer[0]') - is the first column (of 8 per character) of the 'top' (8bit) part of the first included ASCII character (ASCII[32]), and, 
initial $readmemh("font.hex",fontBuffer); // the following byte ('fontBuffer[1]') is the the 'bottom' (8bit) part of the same column the character. Then ('fontBuffer[2]') is the top byte of the second column of the same ASCII character, and so on...  

// Split up the address from a pixel index to the desired character index column and whether or not we are on the top row:
wire [2:0] columnAddress;
wire topRow;
// Also need a buffer to store the output byte. 
reg [7:0] outputBuffer; 
wire [7:0] chosenChar; // ASCII byte values.  and 'chosenChar' will check if it is in range and if not replace 

// Note:
// If we look back at how we stored our font data (font.hex) -  we stored the first column top byte then the first column second byte then the next column top byte and so on.
// We take the character we want to display, subtract 32 to get the offset from start of memory. Multiply by 16 (by shifting left 4 times) to get the start of the character.
// Add to this the column address multiplied by 2 (again by shifting left by 1) and optionally adding another 1 if we are on the bottom row.
// This can be used to access the exact byte from the font memory needed:
always_ff @(posedge clk) begin 
  outputBuffer <= fontBuffer[((chosenChar - 8'd32) << 4) + (columnAddress << 1) + (topRow? 0 : 1)];
end

// Connecting these up is simple now that we understand the mapping:
assign charAddress = {pixelAddress[9:8],pixelAddress[6:3]}; // The character address is made up of a lower 16 counter and the higher 4 counter for the rows. 
assign columnAddress = pixelAddress[2:0]; // The column address is the last 3 bits,
assign topRow = !pixelAddress[7]; // For the flag which indicates whether we are on the top row or bottom row we can just take a look at bit number 8 where it will be - 0 if we are on the top row and 1 if it is the second iteration and we are on the bottom, so we invert it to match the flag name. 

// Converting a Letter to Pixels
assign chosenChar = ((charOutput >= 32) && (charOutput <= 126)) ? charOutput : 32;  // Check and set if we're in the ASCII limits
assign pixelData = outputBuffer; // Attach the decoded/processed character (byte) from 'pixelAddress' 

endmodule
