// Each slide switch drives the LED above it. Deliberately the simplest thing
// that can possibly work: purely combinational, no clock, no reset, no IP.
// If this fails, the problem is the toolchain or the cable, never the design.
module leds (
    input  wire [3:0] sw,
    output wire [3:0] led
);
    assign led = sw;
endmodule
