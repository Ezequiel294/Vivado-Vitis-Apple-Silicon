// Test 07 — on-chip debug cores.
//
// A free-running counter gives the ILA something to capture, and the VIO
// drives three LEDs so its output is visible without any tooling.
//
// led[3] is a hardware heartbeat driven straight from the counter — NOT from
// the VIO. That separates two failures that would otherwise look identical:
//   heartbeat blinking + VIO LEDs dead  -> design is running, VIO is broken
//   heartbeat dead                      -> design never loaded at all
`timescale 1ns / 1ps

module ila_vio_top (
    input  wire       CLK100MHZ,
    input  wire [3:0] sw,
    output wire [3:0] led
);
    reg [31:0] counter = 32'd0;
    always @(posedge CLK100MHZ) counter <= counter + 1'b1;

    wire [2:0] vio_led;

    // bit 26 of a 100MHz counter is about 0.75 Hz — clearly visible blinking
    assign led = {counter[26], vio_led};

    // Captures the counter and the switches; view in Hardware Manager.
    ila_0 ila_i (
        .clk    (CLK100MHZ),
        .probe0 (counter),
        .probe1 (sw)
    );

    // probe_in0  : Hardware Manager can read the switches
    // probe_out0 : Hardware Manager can drive the LEDs
    vio_0 vio_i (
        .clk        (CLK100MHZ),
        .probe_in0  (sw),
        .probe_out0 (vio_led)
    );
endmodule
