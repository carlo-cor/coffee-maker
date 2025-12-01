`timescale 1ns/1ps
`include "cmach_recipes.svh"

module lcdIp_Top (
    // Clock and Active-Low Reset
    input  wire        CLOCK_50,
    input  wire        KEY,            // active-low reset button

    // 4 UI Pushbuttons (level signals)
    input  wire        BTN_FLAVOR,
    input  wire        BTN_TYPE,
    input  wire        BTN_SIZE,
    input  wire        BTN_START,

    // Sensor Inputs
    input  wire [1:0]  PAPER_LEVEL,
    input  wire        BIN_0_AMPTY,
    input  wire        BIN_1_AMPTY,
    input  wire        ND_AMPTY,
    input  wire        CH_AMPTY,
    input  wire [1:0]  W_PRESSURE,
    input  wire        W_TEMP,
    input  wire        STATUS,

    // Coffee hardware control outputs
    output wire        HEAT_EN,
    output wire        POUROVER_EN,
    output wire        WATER_EN,
    output wire        GRINDER_0_EN,
    output wire        GRINDER_1_EN,
    output wire        PAPER_EN,
    output wire        COCOA_EN,
    output wire        CREAMER_EN,

    // LCD Outputs
    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_ON,
    output wire        LCD_BLON
);

    // Power Enable Initialization
    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

    // Synchronous reset (internal)
    reg rst;
    always @(posedge CLOCK_50) begin
        rst <= ~KEY;
    end

    //===========================================================
    // Recipes (FIXED: cmach_recp outputs packed bits, cast to coffee_recipe_t)
    //===========================================================
    localparam int RECIPE_W = $bits(coffee_recipe_t);

    logic [RECIPE_W-1:0] recipes_bits [0:14];
    coffee_recipe_t      recipes      [0:14];

    cmach_recp u_recipes (.recipes(recipes_bits));

    integer ri;
    always_comb begin
        for (ri = 0; ri < 15; ri = ri + 1)
            recipes[ri] = coffee_recipe_t'(recipes_bits[ri]);
    end

    //===========================================================
    // Coffee control system
    //===========================================================
    wire       cur_flavor;
    wire [2:0] cur_type;
    wire [1:0] cur_size;
    wire [1:0] sys_state;

    coffeeSystem #(
        .CLK_HZ(50_000_000),
        .SPEEDUP_DIV(1)
    ) u_coffee (
        .clk(CLOCK_50),
        .rst(rst),

        .btn_flavor(BTN_FLAVOR),
        .btn_type  (BTN_TYPE),
        .btn_size  (BTN_SIZE),
        .btn_start (BTN_START),

        .PAPER_LEVEL(PAPER_LEVEL),
        .BIN_0_AMPTY(BIN_0_AMPTY),
        .BIN_1_AMPTY(BIN_1_AMPTY),
        .ND_AMPTY(ND_AMPTY),
        .CH_AMPTY(CH_AMPTY),
        .W_PRESSURE(W_PRESSURE),
        .W_TEMP(W_TEMP),
        .STATUS(STATUS),

        .recipes(recipes),

        .cur_flavor(cur_flavor),
        .cur_type(cur_type),
        .cur_size(cur_size),
        .sys_state(sys_state),

        .HEAT_EN(HEAT_EN),
        .POUROVER_EN(POUROVER_EN),
        .WATER_EN(WATER_EN),
        .GRINDER_0_EN(GRINDER_0_EN),
        .GRINDER_1_EN(GRINDER_1_EN),
        .PAPER_EN(PAPER_EN),
        .COCOA_EN(COCOA_EN),
        .CREAMER_EN(CREAMER_EN)
    );

    //===========================================================
    // Your LCD IP interface (unchanged)
    //===========================================================
    reg  [1:0] op;       // 2'b00 = INSTR (RS=0), 2'b01 = DATA (RS=1)
    reg        send;
    reg  [7:0] din;
    wire       busy, systemReady;

    lcdIp u_lcd (
        .clk          (CLOCK_50),
        .userOp       (op),
        .send         (send),
        .reset        (rst),
        .inputCommand (din),
        .lcd_data     (LCD_DATA),
        .lcd_rs       (LCD_RS),
        .lcd_rw       (LCD_RW),
        .lcd_e        (LCD_EN),
        .busy         (busy),
        .systemReady  (systemReady)
    );

    //===========================================================
    // Warning/Error selection + alternation
    //===========================================================
    reg [3:0] err_sel, warn_sel;
    reg err_present, warn_present;

    always @(*) begin
        err_present = 1'b0; warn_present = 1'b0;
        err_sel     = 4'd0; warn_sel     = 4'd0;

        // Errors (force idle behavior handled in coffeeSystem; LCD shows these)
        if (PAPER_LEVEL == 2'b00) begin err_present = 1'b1; err_sel = 4'd3; end // NOT INSTALLED
        else if (PAPER_LEVEL == 2'b01) begin err_present = 1'b1; err_sel = 4'd2; end // EMPTY
        else if (W_PRESSURE == 2'b11) begin err_present = 1'b1; err_sel = 4'd8; end // PRESSURE ERROR
        else if (W_PRESSURE == 2'b10) begin err_present = 1'b1; err_sel = 4'd9; end // HIGH PRESSURE
        else if (STATUS == 1'b0) begin err_present = 1'b1; err_sel = 4'd11; end // HW STATUS ERROR

        // Warnings (alternate with normal display)
        else if (PAPER_LEVEL == 2'b10) begin warn_present = 1'b1; warn_sel = 4'd1; end // FILTER ALMOST EMPTY
        else if (W_PRESSURE == 2'b00)  begin warn_present = 1'b1; warn_sel = 4'd10; end // LOW PRESSURE
        else if (BIN_0_AMPTY)          begin warn_present = 1'b1; warn_sel = 4'd4; end
        else if (BIN_1_AMPTY)          begin warn_present = 1'b1; warn_sel = 4'd5; end
        else if (ND_AMPTY)             begin warn_present = 1'b1; warn_sel = 4'd6; end
        else if (CH_AMPTY)             begin warn_present = 1'b1; warn_sel = 4'd7; end
    end

    // Toggle between normal and warning during warnings
    localparam [31:0] WARN_TOGGLE_TICKS = 32'd50_000_000; // ~1s at 50MHz
    reg [31:0] warn_cnt;
    reg        warn_show;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            warn_cnt  <= 32'd0;
            warn_show <= 1'b0;
        end else if (!warn_present || err_present) begin
            warn_cnt  <= 32'd0;
            warn_show <= 1'b0;
        end else begin
            if (warn_cnt == (WARN_TOGGLE_TICKS-1)) begin
                warn_cnt  <= 32'd0;
                warn_show <= ~warn_show;
            end else begin
                warn_cnt <= warn_cnt + 32'd1;
            end
        end
    end

    wire [3:0] msg_sel =
        (err_present)              ? err_sel  :
        (warn_present && warn_show)? warn_sel :
                                     4'd0;     // normal selection/status display

    //===========================================================
    // LCD message ROMs (existing warnings/errors + new STATUS error)
    //===========================================================
    reg [7:0] m1_l1 [0:15]  = '{"P","a","p","e","r"," ","F","i","l","t","e","r"," ","A","l","m"};
    reg [7:0] m1_l2 [0:15]  = '{"s","t"," ","E","m","p","t","y"," "," "," "," "," "," "," "," "};
    reg [7:0] m2_l1 [0:15]  = '{"P","a","p","e","r"," ","F","i","l","t","e","r"," "," "," "," "};
    reg [7:0] m2_l2 [0:15]  = '{"E","m","p","t","y"," "," "," "," "," "," "," "," "," "," "," "};
    reg [7:0] m3_l1 [0:15]  = '{"P","a","p","e","r"," ","F","i","l","t","e","r"," ","N","O","T"};
    reg [7:0] m3_l2 [0:15]  = '{"I","N","S","T","A","L","L","E","D"," "," "," "," "," "," "," "};
    reg [7:0] m4_l1 [0:15]  = '{"C","o","f","f","e","e"," ","B","i","n"," ","0"," ","A","l","m"};
    reg [7:0] m4_l2 [0:15]  = '{"s","t"," ","E","m","p","t","y"," "," "," "," "," "," "," "," "};
    reg [7:0] m5_l1 [0:15]  = '{"C","o","f","f","e","e"," ","B","i","n"," ","1"," ","A","l","m"};
    reg [7:0] m5_l2 [0:15]  = '{"s","t"," ","E","m","p","t","y"," "," "," "," "," "," "," "," "};
    reg [7:0] m6_l1 [0:15]  = '{"N","o","n","-","D","a","i","r","y"," ","C","r","m","r"," ","A"};
    reg [7:0] m6_l2 [0:15]  = '{"l","m","s","t"," ","E","m","p","t","y"," "," "," "," "," "," "};
    reg [7:0] m7_l1 [0:15]  = '{"C","h","o","c","o","l","a","t","e"," ","P","w","d","r"," ","A"};
    reg [7:0] m7_l2 [0:15]  = '{"l","m","s","t"," ","E","m","p","t","y"," "," "," "," "," "," "};
    reg [7:0] m8_l1 [0:15]  = '{"W","a","t","e","r"," ","P","r","e","s","s","u","r","e"," "," "};
    reg [7:0] m8_l2 [0:15]  = '{"E","r","r","o","r","!"," "," "," "," "," "," "," "," "," "," "};
    reg [7:0] m9_l1 [0:15]  = '{"H","i","g","h"," ","W","a","t","e","r"," "," "," "," "," "," "};
    reg [7:0] m9_l2 [0:15]  = '{"P","r","e","s","s","u","r","e"," "," "," "," "," "," "," "," "};
    reg [7:0] m10_l1[0:15]  = '{"L","o","w"," ","W","a","t","e","r"," "," "," "," "," "," "," "};
    reg [7:0] m10_l2[0:15]  = '{"P","r","e","s","s","u","r","e"," "," "," "," "," "," "," "," "};

    // New STATUS error message (index 11)
    reg [7:0] m11_l1[0:15]  = '{"H","a","r","d","w","a","r","e"," ","S","t","a","t","u","s"," "};
    reg [7:0] m11_l2[0:15]  = '{"E","r","r","o","r"," ","-"," ","S","e","r","v","i","c","e"," "};

    //===========================================================
    // Normal 2-line message generator (selection + state)
    //===========================================================
    function automatic [39:0] drink5(input [2:0] t);
        begin
            case (t)
                3'd0: drink5 = {"M","O","C","H","A"};
                3'd1: drink5 = {"L","A","T","T","E"};
                3'd2: drink5 = {"E","S","P","R"," "}; // short
                3'd3: drink5 = {"A","M","E","R"," "}; // short
                3'd4: drink5 = {"D","R","I","P"," "};
                default: drink5 = {"U","N","K","N"," "};
            endcase
        end
    endfunction

    function automatic [31:0] size4(input [1:0] s);
        begin
            case (s)
                2'd0: size4 = {"1","0","o","z"};
                2'd1: size4 = {"1","6","o","z"};
                2'd2: size4 = {"2","0","o","z"};
                default: size4 = {"?","?","o","z"};
            endcase
        end
    endfunction

    function automatic [127:0] mk_line1;
        input logic f;
        input logic [2:0] t;
        input logic [1:0] s;
        logic [7:0] fch;
        begin
            fch = (f) ? "2" : "1";
            mk_line1 = {"C", fch, " ", drink5(t), " ", size4(s), " ", " ", " "}; // 16 total
        end
    endfunction

    function automatic [127:0] mk_line2;
        input logic [1:0] st;
        begin
            case (st)
                2'd0: mk_line2 = {"P","r","e","s","s"," ","S","T","A","R","T"," "," "," "," "," "}; // 16
                2'd1: mk_line2 = {"H","E","A","T","I","N","G",".",".","."," "," "," "," "," "," "};
                2'd2: mk_line2 = {"B","R","E","W","I","N","G",".",".","."," "," "," "," "," "," "};
                default: mk_line2 = {"R","E","A","D","Y"," "," "," "," "," "," "," "," "," "," "," "};
            endcase
        end
    endfunction

    function automatic [7:0] byte16(input [127:0] s, input [4:0] k);
        begin
            byte16 = s[8*(15-k) +: 8];
        end
    endfunction

    function automatic [7:0] get_byte;
        input [3:0] sel;
        input       line; // 0=line1, 1=line2
        input [4:0] k;
        logic [127:0] L1, L2;
        begin
            if (sel == 4'd0) begin
                L1 = mk_line1(cur_flavor, cur_type, cur_size);
                L2 = mk_line2(sys_state);
                get_byte = (line) ? byte16(L2, k) : byte16(L1, k);
            end else begin
                case (sel)
                    4'd1:  get_byte = line ? m1_l2[k]  : m1_l1[k];
                    4'd2:  get_byte = line ? m2_l2[k]  : m2_l1[k];
                    4'd3:  get_byte = line ? m3_l2[k]  : m3_l1[k];
                    4'd4:  get_byte = line ? m4_l2[k]  : m4_l1[k];
                    4'd5:  get_byte = line ? m5_l2[k]  : m5_l1[k];
                    4'd6:  get_byte = line ? m6_l2[k]  : m6_l1[k];
                    4'd7:  get_byte = line ? m7_l2[k]  : m7_l1[k];
                    4'd8:  get_byte = line ? m8_l2[k]  : m8_l1[k];
                    4'd9:  get_byte = line ? m9_l2[k]  : m9_l1[k];
                    4'd10: get_byte = line ? m10_l2[k] : m10_l1[k];
                    4'd11: get_byte = line ? m11_l2[k] : m11_l1[k];
                    default: get_byte = " ";
                endcase
            end
        end
    endfunction

    //===========================================================
    // LCD init/write FSM (same behavior as yours, but refreshes on msg_sel OR selection/state changes)
    //===========================================================
    localparam [5:0]
        S_PWRUP     = 6'd0,
        S_WAIT1     = 6'd2,
        S_WAIT2     = 6'd4,
        S_WAIT3     = 6'd6,
        S_WAIT_DISPOFF   = 6'd8,
        S_WAIT_CLR        = 6'd10,
        S_WAIT_ENTRY      = 6'd12,
        S_WAIT_DISPON     = 6'd14,
        S_WAITON          = 6'd16,
        S_SET_L1    = 6'd17,  S_WAIT_L1 = 6'd18,
        S_WRITE_L1  = 6'd19,  S_WAIT_WL1= 6'd20,
        S_SET_L2    = 6'd21,  S_WAIT_L2 = 6'd22,
        S_WRITE_L2  = 6'd23,  S_WAIT_WL2= 6'd24,
        S_IDLE      = 6'd25,
        S_CLR_SW    = 6'd26,  S_WAIT_ENTRY_SW= 6'd27;

    reg [5:0]  state = S_PWRUP;
    reg [31:0] dly = 0;
    reg [4:0]  idx = 0;

    // 50 MHz delays
    localparam DLY_15MS   = 32'd750_000;
    localparam DLY_5MS    = 32'd250_000;
    localparam DLY_100US  = 32'd5_000;
    localparam DLY_CMD    = 32'd5_000;
    localparam DLY_CLEAR  = 32'd75_000;

    // Change detection (msg_sel OR normal content updates)
    reg [3:0] prev_msg_sel;
    reg       prev_flavor;
    reg [2:0] prev_type;
    reg [1:0] prev_size;
    reg [1:0] prev_sys_state;

    wire normal_changed = (msg_sel == 4'd0) &&
                          ((prev_flavor   != cur_flavor) ||
                           (prev_type     != cur_type)   ||
                           (prev_size     != cur_size)   ||
                           (prev_sys_state!= sys_state));

    wire msg_changed = (msg_sel != prev_msg_sel);

    reg change_detected;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            prev_msg_sel   <= 4'd0;
            prev_flavor    <= 1'b0;
            prev_type      <= 3'd0;
            prev_size      <= 2'd0;
            prev_sys_state <= 2'd0;
            change_detected<= 1'b0;
        end else begin
            if (msg_changed || normal_changed)
                change_detected <= 1'b1;
            else if (state == S_CLR_SW)
                change_detected <= 1'b0;

            prev_msg_sel   <= msg_sel;
            prev_flavor    <= cur_flavor;
            prev_type      <= cur_type;
            prev_size      <= cur_size;
            prev_sys_state <= sys_state;
        end
    end

    always @(posedge CLOCK_50) begin
        if (rst) begin
            state <= S_PWRUP;
            dly   <= 0;
            idx   <= 0;
            op    <= 2'b00;
            din   <= 8'h00;
            send  <= 1'b0;
        end else begin
            send <= 1'b0;

            case (state)
                S_PWRUP: begin
                    if (dly < DLY_15MS) dly <= dly + 1;
                    else begin
                        din   <= 8'h30; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAIT1;
                    end
                end

                S_WAIT1: begin
                    if (!busy && dly >= DLY_5MS) begin
                        din   <= 8'h30; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAIT2;
                    end else dly <= dly + 1;
                end

                S_WAIT2: begin
                    if (!busy && dly >= DLY_100US) begin
                        din   <= 8'h30; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAIT3;
                    end else dly <= dly + 1;
                end

                S_WAIT3: begin
                    if (!busy && dly >= DLY_100US) begin
                        din   <= 8'h38; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAIT_DISPOFF;
                    end else dly <= dly + 1;
                end

                S_WAIT_DISPOFF: begin
                    if (!busy && dly >= DLY_CMD) begin
                        din   <= 8'h08; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAIT_CLR;
                    end else dly <= dly + 1;
                end

                S_WAIT_CLR: begin
                    if (!busy && dly >= DLY_CMD) begin
                        din   <= 8'h01; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAIT_ENTRY;
                    end else dly <= dly + 1;
                end

                S_WAIT_ENTRY: begin
                    if (!busy && dly >= DLY_CLEAR) begin
                        din   <= 8'h06; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAIT_DISPON;
                    end else dly <= dly + 1;
                end

                S_WAIT_DISPON: begin
                    if (!busy && dly >= DLY_CMD) begin
                        din   <= 8'h0C; op <= 2'b00; send <= 1'b1;
                        dly   <= 0; state <= S_WAITON;
                    end else dly <= dly + 1;
                end

                S_WAITON: begin
                    if (!busy && dly >= DLY_CMD) begin
                        state <= S_SET_L1;
                    end else dly <= dly + 1;
                end

                S_SET_L1: begin
                    if (!busy) begin
                        din <= 8'h80; op <= 2'b00; send <= 1'b1;
                        dly <= 0; idx <= 0; state <= S_WAIT_L1;
                    end
                end

                S_WAIT_L1: begin
                    if (!busy && dly >= DLY_CMD) state <= S_WRITE_L1;
                    else dly <= dly + 1;
                end

                S_WRITE_L1: begin
                    if (!busy) begin
                        din <= get_byte(msg_sel, 1'b0, idx);
                        op  <= 2'b01; send <= 1'b1;
                        dly <= 0; state <= S_WAIT_WL1;
                    end
                end

                S_WAIT_WL1: begin
                    if (!busy && dly >= DLY_CMD) begin
                        if (idx < 5'd15) begin
                            idx <= idx + 1; state <= S_WRITE_L1;
                        end else begin
                            idx <= 0; state <= S_SET_L2;
                        end
                    end else dly <= dly + 1;
                end

                S_SET_L2: begin
                    if (!busy) begin
                        din <= 8'hC0; op <= 2'b00; send <= 1'b1;
                        dly <= 0; state <= S_WAIT_L2;
                    end
                end

                S_WAIT_L2: begin
                    if (!busy && dly >= DLY_CMD) state <= S_WRITE_L2;
                    else dly <= dly + 1;
                end

                S_WRITE_L2: begin
                    if (!busy) begin
                        din <= get_byte(msg_sel, 1'b1, idx);
                        op  <= 2'b01; send <= 1'b1;
                        dly <= 0; state <= S_WAIT_WL2;
                    end
                end

                S_WAIT_WL2: begin
                    if (!busy && dly >= DLY_CMD) begin
                        if (idx < 5'd15) begin
                            idx <= idx + 1; state <= S_WRITE_L2;
                        end else begin
                            idx <= 0; state <= S_IDLE;
                        end
                    end else dly <= dly + 1;
                end

                S_IDLE: begin
                    if (change_detected && !busy) state <= S_CLR_SW;
                end

                S_CLR_SW: begin
                    if (!busy) begin
                        din <= 8'h01; op <= 2'b00; send <= 1'b1;
                        dly <= 0; state <= S_WAIT_ENTRY_SW;
                    end
                end

                S_WAIT_ENTRY_SW: begin
                    if (!busy && dly >= DLY_CLEAR) state <= S_SET_L1;
                    else dly <= dly + 1;
                end

                default: state <= S_PWRUP;
            endcase
        end
    end

endmodule
