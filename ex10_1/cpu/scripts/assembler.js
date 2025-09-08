// < The Assembler >
// An assembler, simply takes in assembly code and performs the mapping for us to binary form. We also have the added .org preprocessor we used to specify where the next lines of code are positioned in memory making jumps easier.
// To get started create a file in the scripts folder called assembler.js:

const fs = require('fs');
const path = require('path');

const file = process.argv[2];
if (!file) {
    console.error('No file supplied, usage `node scripts/assembler.js <filename>`');
    process.exit(1);
}
try {
    const fileStat = fs.statSync(file);

    if (fileStat.isDirectory()) {
        console.error(`Supplied file (${file}) is a directory`);
        process.exit(1);
    }
} catch(e) {
    if (e.code === 'ENOENT') {
        console.error(`Could not find file ${file}`);
        process.exit(1);
    }
}

// We start off our program getting the assembly file's name from argv. This variable stores all command line arguments from the terminal that were specified when running the script. So for example if we run in the terminal node
// assembler.js counter.prog then argv[0] would be node argv[1] would be the script itself assembler.js and argv[2] should be the name of our assembly script counter.prog
// The rest of the code here just does some checks, like making sure a file was specified, making sure the file exists, and making sure the file is not a directory, but rather a standard file.

// After this we need to load the file in and split it up into seperate lines of code:
const fileContents = fs.readFileSync(file).toString();
const lines = fileContents.split('\n').map((line) => line.split(';').shift().trim()).filter((line) => !!line);

// The first line reads the file as a string into fileContents. The next line splits the file up into seperate lines and maps each line in-order to clean it up. The map function is called on an array, and you pass it another function,
//  it will then send each value from the array into the function, and the map function will return a new array, where each value is replaced with whatever the function returns.
// Here we take each line of code, and return a new string which is the line split by ; which we will use to start a comment, So if we had a line like: ADD A ; add a to ac the the split would turn this into an array of two elements: 
// ['ADD A ', 'add a to ac']. We then call shift on this array to only take the first element, as we don't care about the comment, in our example this would return 'ADD A ' and then we call trim to remove any whitespace characters
// from each end, basically removing the extra spaces leaving us with 'ADD A'.
// After mapping our array elements, we also call filter which will remove any empty lines, leaving us with only full lines of code.
// Next we can create a map to store what goes in each memory address:
let pc = 0;
const memoryMap = {}

// pc will be a running counter to store where we are in memory, allowing for our .org preprocessor to modify it.

// Next we will create an array of regular expressions to match the commands being entered, We could have used simple text matching for most commands, but the commands with constant parameters won't be an exact match so we need to use 
// something like "regular expressions" to dynamically match them.
const commands = [
    { regex: /^CLR A$/i,  byte: 0b00001000 },
    { regex: /^CLR B$/i,  byte: 0b00000100 },
    { regex: /^CLR BTN$/i,  byte: 0b00000010 },
    { regex: /^CLR AC$/i, byte: 0b00000001 },
    { regex: /^ADD A$/i,  byte: 0b00011000 },
    { regex: /^ADD B$/i,  byte: 0b00010100 },
    { regex: /^ADD C$/i,  byte: 0b00010010 },
    { regex: /^ADD ([0-9A-F]+?)([HBD]?)$/i,  byte: 0b10010001, hasConstant: true },
    { regex: /^STA A$/i,   byte: 0b00101000 },
    { regex: /^STA B$/i,   byte: 0b00100100 },
    { regex: /^STA C$/i,   byte: 0b00100010 },
    { regex: /^STA LED$/i, byte: 0b00100001 },
    { regex: /^INV A$/i,  byte: 0b00111000 },
    { regex: /^INV B$/i,  byte: 0b00110100 },
    { regex: /^INV C$/i,  byte: 0b00110010 },
    { regex: /^INV AC$/i, byte: 0b00110001 },
    { regex: /^PRNT A$/i,  byte: 0b01001000 },
    { regex: /^PRNT B$/i,  byte: 0b01000100 },
    { regex: /^PRNT C$/i,  byte: 0b01000010 },
    { regex: /^PRNT ([0-9A-F]+?)([HBD]?)$/i,  byte: 0b11000001, hasConstant: true },
    { regex: /^JMPZ A$/i,  byte: 0b01011000 },
    { regex: /^JMPZ B$/i,  byte: 0b01010100 },
    { regex: /^JMPZ C$/i,  byte: 0b01010010 },
    { regex: /^JMPZ ([0-9A-F]+?)([HBD]?)$/i,  byte: 0b11010001, hasConstant: true },
    { regex: /^WAIT A$/i,  byte: 0b01101000 },
    { regex: /^WAIT B$/i,  byte: 0b01100100 },
    { regex: /^WAIT C$/i,  byte: 0b01100010 },
    { regex: /^WAIT ([0-9A-F]+?)([HBD]?)$/i,  byte: 0b11100001, hasConstant: true },
    { regex: /^HLT$/i,  byte: 0b01110000 },
];

// In a regular expression the ^ means start of string and the $ mean the end of a string. Regular expressions also use / instead of ' to wrap the string and the added i flag after each regular expression tell it that it is case insensitive.
// So most of the entries here are exact matches, for example if we see INV AC this should be mapped to the byte 0b00110001. But the commands with a constant parameter have two sets of brackets, denoting to capture groups. This means we tell 
// the regular expression engine to capture whatever is between the brackets and store it whenever we perform a match on this regular expression.
// Inside instead of having a constant string, we have a range of allowed characters. So for constant parameters we can accepts any number and the letters a-f to also support hex numbers. To different between the different number systems we 
// also have the second capture group where you can optionally end the number off with H for hex, B for binary and D for decimal, this will default to decimal if nothing is specified. For these special cases we also add a flag hasConstant and 
// set it to true so that we will know to add another byte with the constant value.
// With all our commands defined, we can now go over each line of code and perform the conversion:
for (const line of lines) {
    const orgMatch = line.match(/\.org ([0-9A-F]+)([HBD])?/i);
    if (orgMatch) {
        const memoryAddressStr = orgMatch[1];
        const type = (orgMatch[2] || 'd').toLowerCase();
        const memoryAddress = parseInt(memoryAddressStr, type == 'd' ? 10 : type == 'h' ? 16 : 2);
        pc = memoryAddress;
        continue;
    }
    for (const command of commands) {
        const commandMatch = line.match(command.regex);
        if (commandMatch) {
            memoryMap[pc] = command.byte;
            pc += 1;
            if (command.hasConstant) {
                const constantStr = commandMatch[1];
                const constantType = (commandMatch[2] || 'd').toLowerCase();
                const constant = parseInt(constantStr, constantType == 'd' ? 10 : constantType == 'h' ? 16 : 2);
                const constantSized = constant % 256;
                if (constant !== constantSized) {
                    console.warn(`Line ${line} has an invalid constant`);
                }
                memoryMap[pc] = constantSized;
                pc += 1;
            }
            break;
        }
    }
}


// We start off by checking if the line matches our .org preprocessor. In which case we take the two values captured which are the memory address and the number type (like hex, decimal or binary). We use parseInt with the correct base to convert 
// the address from string into a number and we set pc to this number so that the next command we go over will be at this address.
// If the current line wasn't an .org preprocessor directive, we go through all our command matchers until we find one that works. Once we found a match we store the byte version in our memory map at the address pointed to by pc.
// The rest of the code just parses the constant parameter similar to how we did it with the .org preprocessor. this constant parameter also gets stored as the next byte in our memory map.
// Now after this loop we don't really have a complete array of bytes we can use as our bytecode, instead we have a map between addresses and bytecode, somethings like:

// {
//     0: 0b01101000,
//     1: 0b01000100,
//     10: 0b01110000
// }

// In this example we would need an array of 11 bytes, where only 3 of the bytes are defined and the rest are blank. These gaps are created because of the .org preprocessor.
// To convert this to an array of bytes, we first need to know what the largest address is:
const largestAddress = Object.keys(memoryMap)
    .map((key) => +key)
    .sort((a, b) => a > b ? -1 : a < b ? 1 : 0)
    .shift();

if (typeof largestAddress === 'undefined') {
    console.error('No code to assemble');
    process.exit(1);
}

// We take all the keys from our map using Object.keys which gives us back an array of the keys as strings, which is essentially all the addresses defined in our program. Next we convert the keys from strings to numbers using the + operator again
// using the map function to convert each element in our array.
// Once converted to numbers, we sort the addresses, the sort method accepts a function that receives two elements in the array a and b, the function then needs to return -1 if a should be placed before b, return 1 if a should be after b and
// return 0 if they have the same sort rank.
// Once sorted, the highest value should be the first element, so we can call shift on the array to give us the first element.
// Once we have the largest element, we just perform a check to make sure we have do in fact have an address, which should be the case unless the entire assembly program was empty.
// Now that we know the largest address we can create an array of this size to store all the bytes of our program:
const byteArray = new Array(largestAddress + 1);
for (let i = 0; i <= largestAddress; i += 1) {
    byteArray[i] = (i in memoryMap) ? memoryMap[i] : 0;
}

// For each byte in the array, we either set it to the value in memoryMap if it exists there, and if not we set that byte to zero.
// With our array ready, we simply need to write it to a file in binary form:
const filename = file.replace('.prog', '.bin');
fs.writeFileSync(filename, Buffer.from(byteArray));
console.log("Assembled Program");

// We take the input file and replace the .prog extension with .bin and then write the .bin file with a binary buffer from our byte array.
// With that we can test it on our counter by running the following from a terminal:
// > node scripts/assembler.js programs/counter.prog

// Looking at the resulting bin file in a hex editor we can see it outputted the following:
//
//...


// You can see our program starts off with 4 bytes, then we jump to line 10 (or 0a) we then get 6 bytes padding until address 10 where we have the rest of our program. Total size of our program is 26 bytes.
// To write this to the tang nano you can run from the terminal:
// > openFPGALoader -b tangnano9k --external-flash ./programs/counter.bin