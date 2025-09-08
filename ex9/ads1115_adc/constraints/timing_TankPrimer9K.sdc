/* This is the main (external) clock that Sipeed Tang Nano 9K Board uses - a 27 [MHz] Clock Source */
create_clock -name EXT_CLK -period 37.037 -waveform {0 18.518} [get_ports {EXT_CLK}]

