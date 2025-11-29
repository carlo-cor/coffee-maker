//==============================================================
// lcdIp: simple 8-bit HD44780 write engine (instruction/data)
// RS=0 for instructions, RS=1 for data. R/W is always 0.
//==============================================================
module lcdIp (
    input  wire       clk,
    input  wire [1:0] userOp,         // 00=INSTR, 01=DATA
    input  wire       send,
    input  wire       reset,
    input  wire [7:0] inputCommand,
    output reg  [7:0] lcd_data,
    output reg        lcd_rs,
    output reg        lcd_rw,
    output reg        lcd_e,
    output reg        busy,
    output reg        systemReady
);
    localparam OP_INSTR = 2'b00;
    localparam OP_DATA  = 2'b01;

    typedef enum logic [2:0] { INIT_WAIT, IDLE, LOAD, SETUP, E_HIGH, E_LOW, WAIT_DONE } state_t;
    state_t st;

    reg [7:0] cmd_latched;
    reg [1:0] op_latched;
    reg [19:0] t; // enough for ~1.5ms at 50MHz

    // timing @50MHz
    localparam integer T_INIT   = 750_000;  // ~15ms after power-up
    localparam integer T_SETUP  = 4;        // >=80ns setup (4 cycles @20ns)
    localparam integer T_E_PW   = 1000;      // 2 µs E high
    localparam integer T_E_LOW  = 1000;      // 2 µs guard before wait
    localparam integer T_CMD    = 2_500;    // 50 µs (>37 µs)
    localparam integer T_CLEAR  = 100_000;  // 2 ms (>1.52 ms)

    wire is_clear_or_home = (op_latched==OP_INSTR) && ((cmd_latched==8'h01) || (cmd_latched==8'h02));

    // FSM
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            st <= INIT_WAIT; t <= T_INIT;
            lcd_data <= 8'h00;
            lcd_rs   <= 1'b0;
            lcd_rw   <= 1'b0;
            lcd_e    <= 1'b0;
            busy     <= 1'b1;
            systemReady <= 1'b0;
            cmd_latched <= 8'h00;
            op_latched  <= OP_INSTR;
        end else begin
            // defaults
            lcd_rw <= 1'b0; // always write
            systemReady <= (st==IDLE);

            case (st)
                INIT_WAIT: begin
                    busy <= 1'b1; lcd_e <= 1'b0;
                    if (t!=0) t <= t-1;
                    else begin st <= IDLE; busy <= 1'b0; end
                end

                IDLE: begin
                    busy <= 1'b0; lcd_e <= 1'b0;
                    if (send) begin
                        cmd_latched <= inputCommand;
                        op_latched  <= userOp;
                        st <= LOAD;
                    end
                end

                LOAD: begin
                    // Place RS and DATA and then wait a few cycles before E↑
                    busy     <= 1'b1;
                    lcd_rs   <= (op_latched==OP_DATA);
                    lcd_data <= cmd_latched;
                    t        <= T_SETUP;
                    st       <= SETUP;
                end

                SETUP: begin
                    // Meet HD44780 address/data setup time before toggling E
                    if (t!=0) t <= t-1;
                    else begin
                        t  <= T_E_PW;
                        st <= E_HIGH;
                    end
                end

                E_HIGH: begin
                    lcd_e <= 1'b1;
                    if (t!=0) t <= t-1;
                    else begin
                        t  <= T_E_LOW;
                        st <= E_LOW; // falling edge latches into LCD
                    end
                end

                E_LOW: begin
                    lcd_e <= 1'b0;
                    if (t!=0) t <= t-1;
                    else begin
                        t  <= is_clear_or_home ? T_CLEAR : T_CMD;
                        st <= WAIT_DONE;
                    end
                end

                WAIT_DONE: begin
                    if (t!=0) t <= t-1;
                    else begin
                        st <= IDLE; busy <= 1'b0;
                    end
                end
            endcase
        end
    end
endmodule
