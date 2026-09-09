// Self-checking testbench: sweeps all 512 input combinations and compares
// against Verilog's own arithmetic. Prints a machine-readable verdict so the
// test can pass or fail without anyone reading a waveform.
`timescale 1ns / 1ps

module adder4_tb;
    reg  [3:0] a, b;
    reg        cin;
    wire [3:0] sum;
    wire       cout;

    integer errors = 0;
    integer i, j, k;

    adder4 dut (.a(a), .b(b), .cin(cin), .sum(sum), .cout(cout));

    initial begin
        // A waveform database, so the same run can also be inspected by eye
        // in the Vivado GUI (see README).
        $dumpfile("adder4_tb.vcd");
        $dumpvars(0, adder4_tb);

        for (i = 0; i < 16; i = i + 1) begin
            for (j = 0; j < 16; j = j + 1) begin
                for (k = 0; k < 2; k = k + 1) begin
                    a = i[3:0]; b = j[3:0]; cin = k[0];
                    #1;
                    if ({cout, sum} !== (i + j + k)) begin
                        errors = errors + 1;
                        $display("MISMATCH a=%0d b=%0d cin=%0d -> got %0d, expected %0d",
                                 i, j, k, {cout, sum}, i + j + k);
                    end
                end
            end
        end

        $display("CHECKED 512 vectors, %0d mismatches", errors);
        if (errors == 0) $display("TEST PASS");
        else             $display("TEST FAIL");
        $finish;
    end
endmodule
