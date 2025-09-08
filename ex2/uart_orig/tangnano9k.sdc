/* This is the main (external) clock that Sipeed Tang Nano 9K Board uses */
create_clock -name clk -period 37.037 -waveform {0 18.518} [get_ports {clk}]

