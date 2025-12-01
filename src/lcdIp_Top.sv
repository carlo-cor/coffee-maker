//======================== lcdIp_Top.sv ========================
`timescale 1ns/1ps
`include "cmach_recipes.svh"

module lcdIp_Top (
    input  wire        CLOCK_50,
    input  wire        KEY,            // active-low reset button

    input  wire        BTN_FLAVOR,
    input  wire        BTN_TYPE,
    input  wire        BTN_SIZE,
    input  wire        BTN_START,

    input  wire [1:0]  PAPER_LEVEL,
    input  wire        BIN_0_AMPTY,
    input  wire        BIN_1_AMPTY,
    input  wire        ND_AMPTY,
    input  wire        CH_AMPTY,
    input  wire [1:0]  W_PRESSURE,
    input  wire        W_TEMP,
    input  wire        STATUS,

    output wire        HEAT_EN,
    output wire        POUROVER_EN,
    output wire        WATER_EN,
    output wire        GRINDER_0_EN,
    output wire        GRINDER_1_EN,
    output wire        PAPER_EN,
    output wire        COCOA_EN,
    output wire        CREAMER_EN,

    output wire [7:0]  LCD_DATA,
    output wire        LCD_RS,
    output wire        LCD_RW,
    output wire        LCD_EN,
    output wire        LCD_ON,
    output wire        LCD_BLON
);

    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

    // Synchronous reset (internal)
    reg rst;
    always @(posedge CLOCK_50) begin
        rst <= ~KEY;
    end

    //===========================================================
    // Recipes
    //===========================================================
    logic [$bits(coffee_recipe_t)-1:0] recipes [0:14];
    cmach_recp u_recipes (.recipes(recipes));

    //===========================================================
    // Coffee control system
    //===========================================================
    wire       cur_flavor;
    wire [2:0] cur_type;
    wire [1:0] cur_size;
    wire [1:0] sys_state;

    wire [15:0] coffee_err_mask;
    wire [2:0]  brew_phase;
    wire [4:0]  brew_progress16;

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
        .CREAMER_EN(CREAMER_EN),

        .err_mask(coffee_err_mask),
        .brew_phase(brew_phase),
        .brew_progress16(brew_progress16)
    );

    //===========================================================
    // LCD IP interface (unchanged)
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
    // ERROR/WARN cycling selection
    //===========================================================
    // Must match coffeeSystem.sv error bit numbers
    localparam int E_PAPER_NOT_INST = 0;
    localparam int E_PAPER_EMPTY    = 1;
    localparam int E_NO_COFFEE0     = 2;
    localparam int E_NO_COFFEE1     = 3;
    localparam int E_NO_CREAMER     = 4;
    localparam int E_NO_CHOC        = 5;
    localparam int E_PRESS_ERR      = 6;
    localparam int E_PRESS_HIGH     = 7;
    localparam int E_STATUS_ERR     = 8;

    // warnings we want to cycle (not blocking)
    localparam int W_FILTER_ALMOST  = 0;
    localparam int W_LOW_PRESSURE   = 1;
    localparam int W_BIN0_EMPTY     = 2;
    localparam int W_BIN1_EMPTY     = 3;
    localparam int W_ND_EMPTY       = 4;
    localparam int W_CH_EMPTY       = 5;

    logic [15:0] warn_mask;

    always @(*) begin
        warn_mask = 16'b0;

        if (PAPER_LEVEL == 2'b10) warn_mask[W_FILTER_ALMOST] = 1'b1; // almost empty
        if (W_PRESSURE  == 2'b00) warn_mask[W_LOW_PRESSURE]  = 1'b1; // low pressure

        if (BIN_0_AMPTY) warn_mask[W_BIN0_EMPTY] = 1'b1;
        if (BIN_1_AMPTY) warn_mask[W_BIN1_EMPTY] = 1'b1;
        if (ND_AMPTY)    warn_mask[W_ND_EMPTY]   = 1'b1;
        if (CH_AMPTY)    warn_mask[W_CH_EMPTY]   = 1'b1;
    end

    wire err_present  = |coffee_err_mask;
    wire warn_present = |warn_mask;

    // 1-second tick
    localparam [31:0] DISP_TICKS = 32'd50_000_000;
    reg [31:0] disp_cnt;
    wire disp_tick = (disp_cnt == (DISP_TICKS-1));

    always @(posedge CLOCK_50) begin
        if (rst) disp_cnt <= 32'd0;
        else if (disp_tick) disp_cnt <= 32'd0;
        else disp_cnt <= disp_cnt + 32'd1;
    end

    //===========================================================
    // PLEASE ENJOY screen (post-brew)
    //===========================================================
    localparam [3:0] ENJOY_SECS = 4'd3;

    reg  [1:0] sys_state_d;
    reg        enjoy_active;
    reg  [3:0] enjoy_cnt;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            sys_state_d   <= 2'd0;
            enjoy_active  <= 1'b0;
            enjoy_cnt     <= 4'd0;
        end else begin
            // previous sys_state for transition detect
            sys_state_d <= sys_state;

            // If we leave SELECT or have an error -> kill enjoy
            if (err_present || (sys_state != 2'd0)) begin
                enjoy_active <= 1'b0;
                enjoy_cnt    <= 4'd0;
            end else begin
                // Detect BREW -> SELECT (brew finished)
                if ((sys_state_d == 2'd2) && (sys_state == 2'd0)) begin
                    enjoy_active <= 1'b1;
                    enjoy_cnt    <= ENJOY_SECS;
                end else if (enjoy_active && disp_tick) begin
                    if (enjoy_cnt <= 4'd1) begin
                        enjoy_active <= 1'b0;
                        enjoy_cnt    <= 4'd0;
                    end else begin
                        enjoy_cnt <= enjoy_cnt - 4'd1;
                    end
                end
            end
        end
    end

    // --------- Quartus-safe priority encoder (NO LOOPS) ---------
    function automatic [3:0] first_set16(input logic [15:0] m);
        begin
            if      (m[0])  first_set16 = 4'd0;
            else if (m[1])  first_set16 = 4'd1;
            else if (m[2])  first_set16 = 4'd2;
            else if (m[3])  first_set16 = 4'd3;
            else if (m[4])  first_set16 = 4'd4;
            else if (m[5])  first_set16 = 4'd5;
            else if (m[6])  first_set16 = 4'd6;
            else if (m[7])  first_set16 = 4'd7;
            else if (m[8])  first_set16 = 4'd8;
            else if (m[9])  first_set16 = 4'd9;
            else if (m[10]) first_set16 = 4'd10;
            else if (m[11]) first_set16 = 4'd11;
            else if (m[12]) first_set16 = 4'd12;
            else if (m[13]) first_set16 = 4'd13;
            else if (m[14]) first_set16 = 4'd14;
            else if (m[15]) first_set16 = 4'd15;
            else            first_set16 = 4'd0;
        end
    endfunction

    // Next-set-bit after cur (wrap), NO LOOPS
    function automatic [3:0] next_set16(input logic [15:0] m, input logic [3:0] cur);
        logic [31:0] mm;
        logic [31:0] rot;
        logic [15:0] r16;
        logic [4:0]  sh;
        logic [3:0]  idx;
        begin
            if (m == 16'b0) begin
                next_set16 = cur;
            end else begin
                mm  = {m, m};
                sh  = {1'b0, cur} + 5'd1;
                rot = (mm >> sh);
                r16 = rot[15:0];

                if (r16 == 16'b0) begin
                    next_set16 = first_set16(m);
                end else begin
                    idx = first_set16(r16);
                    next_set16 = (cur + 4'd1 + idx) & 4'hF;
                end
            end
        end
    endfunction

    reg warn_show;
    reg [3:0] err_code_cur;
    reg [3:0] warn_code_cur;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            warn_show     <= 1'b0;
            err_code_cur  <= 4'd0;
            warn_code_cur <= 4'd0;
        end else if (disp_tick) begin
            if (err_present) begin
                warn_show <= 1'b0;

                if (!coffee_err_mask[err_code_cur])
                    err_code_cur <= first_set16(coffee_err_mask);
                else
                    err_code_cur <= next_set16(coffee_err_mask, err_code_cur);

            end else if (warn_present) begin
                warn_show <= ~warn_show;

                // advance warning only when we're about to show a warning line
                if (!warn_show) begin
                    if (!warn_mask[warn_code_cur])
                        warn_code_cur <= first_set16(warn_mask);
                    else
                        warn_code_cur <= next_set16(warn_mask, warn_code_cur);
                end

            end else begin
                warn_show <= 1'b0;
            end
        end
    end

    function automatic [3:0] map_err_code_to_msg(input logic [3:0] code);
        begin
            case (code)
                E_PAPER_EMPTY:    map_err_code_to_msg = 4'd2;
                E_PAPER_NOT_INST: map_err_code_to_msg = 4'd3;
                E_PRESS_ERR:      map_err_code_to_msg = 4'd8;
                E_PRESS_HIGH:     map_err_code_to_msg = 4'd9;
                E_STATUS_ERR:     map_err_code_to_msg = 4'd11;

                E_NO_COFFEE0:     map_err_code_to_msg = 4'd12;
                E_NO_COFFEE1:     map_err_code_to_msg = 4'd13;
                E_NO_CHOC:        map_err_code_to_msg = 4'd14;
                E_NO_CREAMER:     map_err_code_to_msg = 4'd15;

                default:          map_err_code_to_msg = 4'd11;
            endcase
        end
    endfunction

    function automatic [3:0] map_warn_code_to_msg(input logic [3:0] code);
        begin
            case (code)
                W_FILTER_ALMOST: map_warn_code_to_msg = 4'd1;
                W_LOW_PRESSURE:  map_warn_code_to_msg = 4'd10;

                W_BIN0_EMPTY:    map_warn_code_to_msg = 4'd4;
                W_BIN1_EMPTY:    map_warn_code_to_msg = 4'd5;
                W_ND_EMPTY:      map_warn_code_to_msg = 4'd6;
                W_CH_EMPTY:      map_warn_code_to_msg = 4'd7;

                default:         map_warn_code_to_msg = 4'd1;
            endcase
        end
    endfunction

    // During "PLEASE ENJOY", suppress warnings (but NOT errors)
    wire warn_show_eff = (warn_present && warn_show && !enjoy_active);

    wire [3:0] msg_sel =
        (err_present)       ? map_err_code_to_msg(err_code_cur) :
        (warn_show_eff)     ? map_warn_code_to_msg(warn_code_cur) :
                              4'd0;

    //===========================================================
    // LCD message ROMs
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
    reg [7:0] m11_l1[0:15]  = '{"H","a","r","d","w","a","r","e"," ","S","t","a","t","u","s"," "};
    reg [7:0] m11_l2[0:15]  = '{"E","r","r","o","r"," ","-"," ","S","e","r","v","i","c","e"," "};

    // NEW selection-blocking errors (12..15)
    reg [7:0] m12_l1[0:15]  = '{"N","o"," ","C","o","f","f","e","e"," ","B","i","n"," ","0"," "};
    reg [7:0] m12_l2[0:15]  = '{"C","a","n","n","o","t"," ","e","x","e","c","u","t","e"," "," "};

    reg [7:0] m13_l1[0:15]  = '{"N","o"," ","C","o","f","f","e","e"," ","B","i","n"," ","1"," "};
    reg [7:0] m13_l2[0:15]  = '{"C","a","n","n","o","t"," ","e","x","e","c","u","t","e"," "," "};

    reg [7:0] m14_l1[0:15]  = '{"N","o"," ","C","h","o","c","o","l","a","t","e"," "," "," "," "};
    reg [7:0] m14_l2[0:15]  = '{"C","a","n","n","o","t"," ","e","x","e","c","u","t","e"," "," "};

    reg [7:0] m15_l1[0:15]  = '{"N","o"," ","C","r","e","a","m","e","r"," "," "," "," "," "," "};
    reg [7:0] m15_l2[0:15]  = '{"C","a","n","n","o","t"," ","e","x","e","c","u","t","e"," "," "};

    //===========================================================
    // Normal 2-line message generator (selection + state/progress)
    //===========================================================
    function automatic [39:0] drink5(input [2:0] t);
        begin
            case (t)
                3'd0: drink5 = {"M","O","C","H","A"};
                3'd1: drink5 = {"L","A","T","T","E"};
                3'd2: drink5 = {"E","S","P","R"," "};
                3'd3: drink5 = {"A","M","E","R"," "};
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

    function automatic [127:0] mk_line1(input logic f, input logic [2:0] t, input logic [1:0] s);
        logic [7:0] fch;
        begin
            fch = (f) ? "2" : "1";
            mk_line1 = {"C", fch, " ", drink5(t), " ", size4(s), " ", " ", " "};
        end
    endfunction

    function automatic [31:0] phase4(input logic [2:0] ph);
        begin
            case (ph)
                3'd0: phase4 = {"P","A","P","R"};
                3'd1: phase4 = {"G","R","N","D"};
                3'd2: phase4 = {"C","O","C","O"};
                3'd3: phase4 = {"P","O","U","R"};
                3'd4: phase4 = {"W","A","T","R"};
                default: phase4 = {"D","O","N","E"};
            endcase
        end
    endfunction

    function automatic [95:0] bar12(input logic [3:0] filled);
        begin
            bar12 = {
                (filled> 0 ? "#" : "-"),
                (filled> 1 ? "#" : "-"),
                (filled> 2 ? "#" : "-"),
                (filled> 3 ? "#" : "-"),
                (filled> 4 ? "#" : "-"),
                (filled> 5 ? "#" : "-"),
                (filled> 6 ? "#" : "-"),
                (filled> 7 ? "#" : "-"),
                (filled> 8 ? "#" : "-"),
                (filled> 9 ? "#" : "-"),
                (filled>10 ? "#" : "-"),
                (filled>11 ? "#" : "-")
            };
        end
    endfunction

    function automatic [127:0] mk_line2(input logic [1:0] st, input logic [2:0] ph, input logic [4:0] prog16);
        logic [3:0] filled12;
        begin
            case (st)
                2'd0: mk_line2 = {"P","r","e","s","s"," ","S","T","A","R","T"," "," "," "," "," "};
                2'd1: mk_line2 = {"H","E","A","T","I","N","G",".",".","."," "," "," "," "," "," "};
                2'd2: begin
                    if (prog16 >= 5'd16) filled12 = 4'd12;
                    else filled12 = (prog16 * 12) / 16;
                    mk_line2 = { bar12(filled12), phase4(ph) };
                end
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
                if (enjoy_active) begin
                    L1 = {"C","o","f","f","e","e"," ","C","o","m","p","l","e","t","e"," "};
                    L2 = {"P","l","e","a","s","e"," ","E","n","j","o","y","!"," "," "," "};
                end else begin
                    L1 = mk_line1(cur_flavor, cur_type, cur_size);
                    L2 = mk_line2(sys_state, brew_phase, brew_progress16);
                end
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
                    4'd12: get_byte = line ? m12_l2[k] : m12_l1[k];
                    4'd13: get_byte = line ? m13_l2[k] : m13_l1[k];
                    4'd14: get_byte = line ? m14_l2[k] : m14_l1[k];
                    4'd15: get_byte = line ? m15_l2[k] : m15_l1[k];
                    default: get_byte = " ";
                endcase
            end
        end
    endfunction

    //===========================================================
    // LCD init/write FSM (refreshes on msg_sel OR normal content changes)
    //===========================================================
    localparam [5:0]
        S_PWRUP          = 6'd0,
        S_WAIT1          = 6'd2,
        S_WAIT2          = 6'd4,
        S_WAIT3          = 6'd6,
        S_WAIT_DISPOFF   = 6'd8,
        S_WAIT_CLR       = 6'd10,
        S_WAIT_ENTRY     = 6'd12,
        S_WAIT_DISPON    = 6'd14,
        S_WAITON         = 6'd16,
        S_SET_L1         = 6'd17,  S_WAIT_L1 = 6'd18,
        S_WRITE_L1       = 6'd19,  S_WAIT_WL1= 6'd20,
        S_SET_L2         = 6'd21,  S_WAIT_L2 = 6'd22,
        S_WRITE_L2       = 6'd23,  S_WAIT_WL2= 6'd24,
        S_IDLE           = 6'd25,
        S_CLR_SW         = 6'd26,  S_WAIT_ENTRY_SW= 6'd27;

    reg [5:0]  state = S_PWRUP;
    reg [31:0] dly = 0;
    reg [4:0]  idx = 0;

    localparam DLY_15MS   = 32'd750_000;
    localparam DLY_5MS    = 32'd250_000;
    localparam DLY_100US  = 32'd5_000;
    localparam DLY_CMD    = 32'd5_000;
    localparam DLY_CLEAR  = 32'd75_000;

    // Change detection
    reg [3:0] prev_msg_sel;
    reg       prev_flavor;
    reg [2:0] prev_type;
    reg [1:0] prev_size;
    reg [1:0] prev_sys_state;
    reg [2:0] prev_brew_phase;
    reg [4:0] prev_brew_prog;
    reg       prev_enjoy;

    wire msg_changed = (msg_sel != prev_msg_sel);

    wire normal_changed = (msg_sel == 4'd0) &&
                          ((prev_enjoy      != enjoy_active) ||
                           (prev_flavor     != cur_flavor) ||
                           (prev_type       != cur_type)   ||
                           (prev_size       != cur_size)   ||
                           (prev_sys_state  != sys_state)  ||
                           (prev_brew_phase != brew_phase) ||
                           (prev_brew_prog  != brew_progress16));

    reg change_detected;

    always @(posedge CLOCK_50) begin
        if (rst) begin
            prev_msg_sel    <= 4'd0;
            prev_flavor     <= 1'b0;
            prev_type       <= 3'd0;
            prev_size       <= 2'd0;
            prev_sys_state  <= 2'd0;
            prev_brew_phase <= 3'd0;
            prev_brew_prog  <= 5'd0;
            prev_enjoy      <= 1'b0;
            change_detected <= 1'b0;
        end else begin
            if (msg_changed || normal_changed)
                change_detected <= 1'b1;
            else if (state == S_CLR_SW)
                change_detected <= 1'b0;

            prev_msg_sel    <= msg_sel;
            prev_flavor     <= cur_flavor;
            prev_type       <= cur_type;
            prev_size       <= cur_size;
            prev_sys_state  <= sys_state;
            prev_brew_phase <= brew_phase;
            prev_brew_prog  <= brew_progress16;
            prev_enjoy      <= enjoy_active;
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
                            idx <= idx + 5'd1; state <= S_WRITE_L1;
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
                            idx <= idx + 5'd1; state <= S_WRITE_L2;
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
