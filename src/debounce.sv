module debounce #(
    parameter int CLK_HZ = 50_000_000,
    parameter int DEBOUNCE_MS = 10
)(
    input  logic clk,
    input  logic rst,
    input  logic noisy,
    output logic clean
);

    localparam int COUNT_MAX = (CLK_HZ/1000)*DEBOUNCE_MS;

    logic [$clog2(COUNT_MAX):0] count;
    logic state;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= 1'b0;
            clean <= 1'b0;
            count <= '0;
        end else begin
            if (noisy != state) begin
                if (count == COUNT_MAX) begin
                    state <= noisy;
                    clean <= noisy;
                    count <= '0;
                end else begin
                    count <= count + 1;
                end
            end else begin
                count <= '0;
            end
        end
    end
endmodule
