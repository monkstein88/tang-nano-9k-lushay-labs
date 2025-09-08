// To load our data we can use things like readmemh or readmemb like we have done in the past, but for this example, we will generate a static verilog ROM to showcase another method.

// So let's start with a script that will take in an image and convert it into the ROMs we will need to display an image.

// Converting Image to ROM
// The script we need to create needs to do a number of things:

// 1. Load in an image file
// 2. Resize to dimensions of LED panel
// 3. Quantize colors to our 3-bit space
// 4. Generate Verilog ROM files
// 5. We will be using node.js but any language can be used. To get started in a terminal window inside a new folder you can run npm init pressing enter multiple times to generate a new package.json so we can keep track of dependencies locally.

// Next, you can run npm install sharp which will install an image-processing library called sharp for node.js that will allow us to process images and extract their pixels. Finally, we can create the script file convert.js where we will go
// through the steps above:

const sharp = require('sharp');
const fs = require('fs');

// usage: node convert.js <image_path>

const imagePath = process.argv[2];
const imageWidth = 64;
const imageHeight = 64;

// We start by loading in the sharp library for working with images and then the fs built-in library for working with the filesystem (to save the Verilog output files). Next, we will accept the image path as a CLI argument and we define the 
// screen size. argv is a variable that stores the command run along with it's arguments, index 0 would store the application being run in our case the Node.js interpreter node, index 1 would be our script (convert.js) which we are passing to 
// be interpreted, finally index 2 would be the first argument to our script which in our case will be the image to convert.
// Images usually store data as 8-bit colors per channel, and we only have 1 bit per color channel, so we will need a way to quantize the color value from the input source color to the destination color of our screen. To do this we will see
// if the color channel is above a threshold (in our case 128/256 which is 50%) if the channel is above 50% on we will light it up on our panel.

// function quantizeColor(value) {
//   return value >= 128 ? 1 : 0;
// }

function convertTo3Bit(r, g, b) {
  return (quantizeColor(b) << 2) | (quantizeColor(g) << 1) | quantizeColor(r);
}
// The convertTo3Bit function just combines the 3 states into a single 3-bit value, red is our least significant bit and blue is our most significant bit, based on how we set up our constraints.

// With these two helper functions, we can create the function to process our image:
async function processImage() {
  try {
    const image = sharp(imagePath);
    const { data, info } = await image
      .resize(imageWidth, imageHeight)
      .raw()
      .toBuffer({ resolveWithObject: true });

    let topHalf = [];
    let bottomHalf = [];

    for (let y = 0; y < imageHeight; y++) {
      for (let x = 0; x < imageWidth; x++) {
        const idx = (imageWidth * y + x) * info.channels;
        const r = data[idx];
        const g = data[idx + 1];
        const b = data[idx + 2];
        const value = convertTo3Bit(r, g, b);

        if (y < imageHeight / 2) {
          topHalf.push(value);
        } else {
          bottomHalf.push(value);
        }
      }
    }

    return { topHalf, bottomHalf };
  } catch (error) {
    console.error('Error processing image:', error);
  }
}

// The function starts by loading in the image by path, we then resize the image to the correct size and get the raw pixels bytes out. The format of this data is a long array where the first element is the red 8-bit value of the first pixel,
// then the green, etc continuing for each channel and pixel in the source image.
// The code creates an array to store the bytes for the top half and bottom half of the screen separately. For each pixel in the image we get the RGB values, convert them to a 3-bit value using our helper functions, and then store it either 
// in the topHalf array or bottomHalf array based on the current line.
// With the image processed and converted into the bytes that we need, we can now generate a ROM file using this data for each half:

// function generateVerilogROM(array, moduleName) {
//     let verilogCode = `module ${moduleName}(input wire clk, input wire [10:0] addr, output reg [2:0] data = 0);\n\n`;
//     verilogCode += `    always @(*) begin\n`;
//     verilogCode += `        case (addr)\n`;
//
//     array.forEach((value, index) => {
//         let binaryAddress = index.toString(2).padStart(11, '0'); // 11-bit binary address
//         let binaryValue = value.toString(2).padStart(3, '0'); // 3-bit binary value
//         verilogCode += `            11'b${binaryAddress}: data <= 3'b${binaryValue};\n`;
//     });
//
//     verilogCode += `            default: data = 3'b000;\n`;
//     verilogCode += `        endcase\n`;
//     verilogCode += `    end\n`;
//     verilogCode += `endmodule\n`;
//
//     return verilogCode;
// }

// For example, a generated file could look something like the following:
//   
//    module ROMTop(
//        input clk, 
//        input [9:0] addr, 
//        output reg [2:0] data = 0
//    );
//   
//        always @(*) begin
//            case (addr)
//                10'b0000000000: data <= 3'b000;
//                10'b0000000001: data <= 3'b001;
//                10'b0000000010: data <= 3'b001;
//                // ... all other addresses
//                10'b1111111110: data <= 3'b000;
//                10'b1111111111: data <= 3'b000;
//                default: data <= 3'b000;
//            endcase
//        end
//    endmodule

// < Generating a 2-bit ROM >
// 
// Code-wise this is a pretty simple change, we can start off by updating our convert.js script to generate a 6-bit ROM instead of our previous 3-bit version:
function quantizeColor(colorVal) {
  const quantizationLevels = 4;
  const stepSize = 256 / quantizationLevels;

  return Math.floor(colorVal / stepSize);
}

function convertTo6Bit(r, g, b) {
  return (quantizeColor(b) << 4) | (quantizeColor(g) << 2) | quantizeColor(r);
}
// The quantization is a bit more generic to support the 4 values per channel, but the general idea is the same as mapping the source 8-bit space into our 2-bit space. Other than that we just need to update the function that generates the Verilog,
// to output 6 bits instead of 3:
function generateVerilogROM(array, moduleName) {
    let verilogCode = `module ${moduleName}(input wire clk, input wire [10:0] addr, output reg [5:0] data = 0);\n\n`;
    verilogCode += `    always @(posedge clk) begin\n`;
    verilogCode += `        case (addr)\n`;

    array.forEach((value, index) => {
        let binaryAddress = index.toString(2).padStart(11, '0'); // 11-bit binary address
        let binaryValue = value.toString(2).padStart(6, '0'); // 6-bit binary value
        verilogCode += `            11'b${binaryAddress}: data <= 6'b${binaryValue};\n`;
    });
    verilogCode += `        endcase\n`;
    verilogCode += `    end\n`;
    verilogCode += `endmodule\n`;

    return verilogCode;
}
// With that done, you can run the script on an image with node convert.js <path to image> to generate the two new ROM files. You can use the following test image which goes through each of the 2-bit colors:

// To wrap up our node.js script, we just need to wire everything up with a main function:
async function main() {
    const { topHalf, bottomHalf } = await processImage();

    const topHalfVerilog = generateVerilogROM(topHalf, 'ROMTop');
    const bottomHalfVerilog = generateVerilogROM(bottomHalf, 'ROMBottom');

    fs.writeFileSync('top_half_rom.sv', topHalfVerilog);
    fs.writeFileSync('bottom_half_rom.sv', bottomHalfVerilog);
    console.log('Generated 2 Verilog ROM files');
}
main();

// This function calls the other two functions generating the Verilog text for both ROMs, it then stores them as files using the fs (filesystem) built-in library. With the script ready you can run it in a terminal with:
//
//   node convert.js ./yt_count.png
//
// Replacing yt_count.png with the path to your own image file. You should see that two Verilog files were created in the directory you ran the script from. With these files created, we can start creating a new driver which will display the image.