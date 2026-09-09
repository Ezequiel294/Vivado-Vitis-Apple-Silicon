// Test 04 — receive bytes from the Mac over the USB-UART, prove the FPGA
// actually processed them, and send them back.
//
// The echo is deliberately NOT a plain loopback: lowercase letters come back
// uppercase. A mirror could be faked by a wire or a driver; case conversion
// can only have happened inside the FPGA.
//
// 9600 baud, 8N1, from the board's 100MHz oscillator: 100e6/9600 = 10417.
`timescale 1ns / 1ps

module uart_rx #(parameter CLKS_PER_BIT = 10417) (
    input  wire       clk,
    input  wire       rx,
    output reg  [7:0] data  = 8'h00,
    output reg        valid = 1'b0
);
    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]  state = IDLE;
    reg [13:0] cnt   = 14'd0;
    reg [2:0]  idx   = 3'd0;

    // Two-stage synchroniser: rx is asynchronous to our clock.
    reg rx_s1 = 1'b1, rx_s2 = 1'b1;
    always @(posedge clk) begin
        rx_s1 <= rx;
        rx_s2 <= rx_s1;
    end

    always @(posedge clk) begin
        valid <= 1'b0;
        case (state)
            IDLE: begin
                cnt <= 14'd0;
                idx <= 3'd0;
                if (rx_s2 == 1'b0) state <= START;      // falling edge = start bit
            end
            START: begin
                // Sample the middle of the start bit; if it went high again
                // it was a glitch, not a real frame.
                if (cnt == CLKS_PER_BIT / 2) begin
                    cnt <= 14'd0;
                    state <= (rx_s2 == 1'b0) ? DATA : IDLE;
                end else cnt <= cnt + 1'b1;
            end
            DATA: begin
                if (cnt == CLKS_PER_BIT - 1) begin
                    cnt <= 14'd0;
                    data[idx] <= rx_s2;                 // LSB first
                    if (idx == 3'd7) state <= STOP;
                    else idx <= idx + 1'b1;
                end else cnt <= cnt + 1'b1;
            end
            STOP: begin
                if (cnt == CLKS_PER_BIT - 1) begin
                    cnt   <= 14'd0;
                    valid <= 1'b1;
                    state <= IDLE;
                end else cnt <= cnt + 1'b1;
            end
        endcase
    end
endmodule


module uart_tx #(parameter CLKS_PER_BIT = 10417) (
    input  wire       clk,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx   = 1'b1,
    output reg        busy = 1'b0
);
    localparam IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    reg [1:0]  state = IDLE;
    reg [13:0] cnt   = 14'd0;
    reg [2:0]  idx   = 3'd0;
    reg [7:0]  shft  = 8'h00;

    always @(posedge clk) begin
        case (state)
            IDLE: begin
                tx   <= 1'b1;
                busy <= 1'b0;
                cnt  <= 14'd0;
                idx  <= 3'd0;
                if (start) begin
                    shft  <= data;
                    busy  <= 1'b1;
                    state <= START;
                end
            end
            START: begin
                tx <= 1'b0;
                if (cnt == CLKS_PER_BIT - 1) begin cnt <= 14'd0; state <= DATA; end
                else cnt <= cnt + 1'b1;
            end
            DATA: begin
                tx <= shft[idx];
                if (cnt == CLKS_PER_BIT - 1) begin
                    cnt <= 14'd0;
                    if (idx == 3'd7) state <= STOP;
                    else idx <= idx + 1'b1;
                end else cnt <= cnt + 1'b1;
            end
            STOP: begin
                tx <= 1'b1;
                if (cnt == CLKS_PER_BIT - 1) begin
                    cnt   <= 14'd0;
                    busy  <= 1'b0;
                    state <= IDLE;
                end else cnt <= cnt + 1'b1;
            end
        endcase
    end
endmodule


module uart_echo (
    input  wire       CLK100MHZ,
    input  wire       uart_txd_in,    // host TX -> FPGA RX
    output wire       uart_rxd_out,   // FPGA TX -> host RX
    output reg  [3:0] led = 4'b0000
);
    wire [7:0] rx_data;
    wire       rx_valid;
    wire       tx_busy;

    reg [7:0] pending = 8'h00;
    reg       have    = 1'b0;
    reg       start   = 1'b0;

    uart_rx rx_i (.clk(CLK100MHZ), .rx(uart_txd_in),
                  .data(rx_data), .valid(rx_valid));
    uart_tx tx_i (.clk(CLK100MHZ), .start(start), .data(pending),
                  .tx(uart_rxd_out), .busy(tx_busy));

    always @(posedge CLK100MHZ) begin
        start <= 1'b0;
        if (rx_valid) begin
            // a..z -> A..Z, everything else unchanged
            pending <= (rx_data >= 8'h61 && rx_data <= 8'h7A) ? (rx_data - 8'd32)
                                                              : rx_data;
            have    <= 1'b1;
            led     <= rx_data[3:0];   // low nibble of the last byte received
        end else if (have && !tx_busy && !start) begin
            start <= 1'b1;
            have  <= 1'b0;
        end
    end
endmodule
