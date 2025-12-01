`timescale 1ns/1ps
`include "cmach_recipes.svh"

module coffeeSystem #(
    parameter int CLK_HZ      = 50_000_000,
    parameter int SPEEDUP_DIV  = 1
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        btn_flavor,
    input  logic        btn_type,
    input  logic        btn_size,
    input  logic        btn_start,

    input  logic [1:0]  PAPER_LEVEL,
    input  logic        BIN_0_AMPTY,
    input  logic        BIN_1_AMPTY,
    input  logic        ND_AMPTY,
    input  logic        CH_AMPTY,
    input  logic [1:0]  W_PRESSURE,
    input  logic        W_TEMP,
    input  logic        STATUS,

    input  logic [$bits(coffee_recipe_t)-1:0] recipes [0:14],

    output logic        cur_flavor,
    output logic [2:0]  cur_type,
    output logic [1:0]  cur_size,

    output logic [1:0]  sys_state,

    output logic        HEAT_EN,
    output logic        POUROVER_EN,
    output logic        WATER_EN,
    output logic        GRINDER_0_EN,
    output logic        GRINDER_1_EN,
    output logic        PAPER_EN,

    output logic        COCOA_EN,
    output logic        CREAMER_EN,

    output logic [15:0] err_mask,

    output logic [2:0]  brew_phase,
    output logic [4:0]  brew_progress16
);

    //============================================================
    // Error bit numbers (MUST match lcdIp_Top.sv mapping)
    //============================================================
    localparam int E_PAPER_NOT_INST = 0;
    localparam int E_PAPER_EMPTY    = 1;
    localparam int E_NO_COFFEE0     = 2;
    localparam int E_NO_COFFEE1     = 3;
    localparam int E_NO_CREAMER     = 4;
    localparam int E_NO_CHOC        = 5;
    localparam int E_PRESS_ERR      = 6;
    localparam int E_PRESS_HIGH     = 7;
    localparam int E_STATUS_ERR     = 8;

    //============================================================
    // Edge detect buttons (one action per press)
    // FIX: prevent spurious "press" right after reset
    //============================================================
    logic bf_d, bt_d, bs_d, bstart_d;
    logic bf_p, bt_p, bs_p, bstart_p;
    logic btns_armed;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bf_d       <= 1'b0;
            bt_d       <= 1'b0;
            bs_d       <= 1'b0;
            bstart_d   <= 1'b0;
            btns_armed <= 1'b0;
        end else begin
            bf_d     <= btn_flavor;
            bt_d     <= btn_type;
            bs_d     <= btn_size;
            bstart_d <= btn_start;

            // after we have sampled the inputs at least once, allow edge pulses
            btns_armed <= 1'b1;
        end
    end

    assign bf_p     = btns_armed & (btn_flavor & ~bf_d);
    assign bt_p     = btns_armed & (btn_type   & ~bt_d);
    assign bs_p     = btns_armed & (btn_size   & ~bs_d);
    assign bstart_p = btns_armed & (btn_start  & ~bstart_d);

    //============================================================
    // Top-level state machine
    //============================================================
    typedef enum logic [1:0] { S_SELECT=2'd0, S_WAIT=2'd1, S_BREW=2'd2 } state_t;
    state_t state;

    // Selections (only change in S_SELECT)
    logic        flavor;
    logic [2:0]  dType;
    logic [1:0]  dSize;

    // Latched selections (captured on successful Start)
    logic        flavor_run;
    logic [2:0]  dType_run;
    logic [1:0]  dSize_run;

    // Outputs show live while selecting, latched while running
    always_comb begin
        sys_state = state;
        if (state == S_SELECT) begin
            cur_flavor = flavor;
            cur_type   = dType;
            cur_size   = dSize;
        end else begin
            cur_flavor = flavor_run;
            cur_type   = dType_run;
            cur_size   = dSize_run;
        end
    end

    //============================================================
    // Recipe lookup (index = type*3 + size) 0..14
    //============================================================
    logic [3:0] rIndex;
    coffee_recipe_t recipe_live;

    always_comb begin
        rIndex       = ( {1'b0,dType} * 4'd3 ) + {2'b0,dSize};
        recipe_live  = coffee_recipe_t'(recipes[rIndex]);
    end

    // Latch recipe when starting (so it cannot change mid-brew)
    coffee_recipe_t recipe_lat;

    // Unpack latched recipe fields (positional)
    logic       r_load_filter, r_add_creamer;
    logic [3:0] r_pour_time, r_hot_water_time, r_grinder_time, r_cocoa_time;
    logic       _unused_HP;

    always_comb begin
        {r_load_filter, _unused_HP, r_pour_time, r_hot_water_time,
         r_grinder_time, r_cocoa_time, r_add_creamer} = recipe_lat;
    end

    // Unpack live recipe fields (for ingredient checks gating Start)
    logic       lv_load_filter, lv_add_creamer;
    logic [3:0] lv_pour_time, lv_hot_water_time, lv_grinder_time, lv_cocoa_time;
    logic       lv_unused_HP;

    always_comb begin
        {lv_load_filter, lv_unused_HP, lv_pour_time, lv_hot_water_time,
         lv_grinder_time, lv_cocoa_time, lv_add_creamer} = recipe_live;
    end

    //============================================================
    // SYSTEM errors (continuous)
    //============================================================
    logic [15:0] sys_err_mask;

    always_comb begin
        sys_err_mask = 16'b0;

        if (PAPER_LEVEL == 2'b00)      sys_err_mask[E_PAPER_NOT_INST] = 1'b1;
        else if (PAPER_LEVEL == 2'b01) sys_err_mask[E_PAPER_EMPTY]    = 1'b1;

        if (W_PRESSURE == 2'b11)      sys_err_mask[E_PRESS_ERR]  = 1'b1;
        else if (W_PRESSURE == 2'b10) sys_err_mask[E_PRESS_HIGH] = 1'b1;

        if (STATUS == 1'b0) sys_err_mask[E_STATUS_ERR] = 1'b1;
    end

    wire sys_error_condition = |sys_err_mask;

    //============================================================
    // INGREDIENT errors (only latched/displayed after Start is pressed)
    //============================================================
    logic [15:0] ing_fail_mask;
    logic [15:0] ing_err_latch;

    always_comb begin
        ing_fail_mask = 16'b0;

        if (lv_grinder_time != 4'd0) begin
            if (!flavor && BIN_0_AMPTY) ing_fail_mask[E_NO_COFFEE0] = 1'b1;
            if ( flavor && BIN_1_AMPTY) ing_fail_mask[E_NO_COFFEE1] = 1'b1;
        end

        if ((lv_cocoa_time != 4'd0) && CH_AMPTY) ing_fail_mask[E_NO_CHOC] = 1'b1;
        if (lv_add_creamer && ND_AMPTY)          ing_fail_mask[E_NO_CREAMER] = 1'b1;
    end

    assign err_mask = sys_err_mask | ing_err_latch;

    // Hold ingredient error on LCD briefly (still in SELECT)
    localparam int TICKS_PER_SEC = (CLK_HZ / SPEEDUP_DIV);
    localparam int ING_ERR_HOLD_SECS = 2;

    logic [31:0] ing_tick_cnt;
    logic [3:0]  ing_secs_left;

    //============================================================
    // Brewing phase machine
    //============================================================
    typedef enum logic [2:0] {
        PH_PAPER=3'd0, PH_GRIND=3'd1, PH_COCOA=3'd2, PH_POUR=3'd3, PH_WATER=3'd4, PH_DONE=3'd5
    } phase_t;

    phase_t phase;
    assign brew_phase = phase;

    logic [31:0] tick_cnt;
    logic [3:0]  sec_left;

    function automatic [3:0] phase_duration(input phase_t p);
        begin
            case (p)
                PH_PAPER: phase_duration = (r_load_filter) ? 4'd1 : 4'd0;
                PH_GRIND: phase_duration = r_grinder_time;
                PH_COCOA: phase_duration = r_cocoa_time;
                PH_POUR:  phase_duration = r_pour_time;
                PH_WATER: phase_duration = r_hot_water_time;
                default:  phase_duration = 4'd0;
            endcase
        end
    endfunction

    function automatic phase_t next_phase(input phase_t p);
        begin
            case (p)
                PH_PAPER: next_phase = PH_GRIND;
                PH_GRIND: next_phase = PH_COCOA;
                PH_COCOA: next_phase = PH_POUR;
                PH_POUR:  next_phase = PH_WATER;
                PH_WATER: next_phase = PH_DONE;
                default:  next_phase = PH_DONE;
            endcase
        end
    endfunction

    function automatic phase_t first_nonzero_phase(input phase_t start_p);
        phase_t p;
        int k;
        begin
            p = start_p;
            for (k = 0; k < 6; k++) begin
                if (p == PH_DONE) begin
                    // keep
                end else if (phase_duration(p) != 4'd0) begin
                    // keep
                end else begin
                    p = next_phase(p);
                end
            end
            first_nonzero_phase = p;
        end
    endfunction

    //============================================================
    // Progress 0..16 across all recipe steps
    //============================================================
    logic [7:0] total_sec;
    logic [7:0] elapsed_sec;

    function automatic [7:0] calc_total_seconds(input coffee_recipe_t r);
        logic ld, ac;
        logic [3:0] pt, hw, gt, ct;
        logic hp;
        begin
            {ld, hp, pt, hw, gt, ct, ac} = r;
            calc_total_seconds = (ld ? 8'd1 : 8'd0) + pt + hw + gt + ct;
            if (calc_total_seconds == 8'd0) calc_total_seconds = 8'd1;
        end
    endfunction

    function automatic [4:0] calc_progress16(input [7:0] el, input [7:0] tot);
        int unsigned num;
        int unsigned den;
        int unsigned q;
        begin
            den = (tot == 0) ? 1 : tot;
            num = el * 16;
            q   = num / den;
            if (q > 16) q = 16;
            calc_progress16 = q[4:0];
        end
    endfunction

    //============================================================
    // State + selection + brew timing
    //============================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= S_SELECT;

            flavor         <= 1'b0;
            dType          <= 3'd0;
            dSize          <= 2'd0;

            flavor_run     <= 1'b0;
            dType_run      <= 3'd0;
            dSize_run      <= 2'd0;

            recipe_lat     <= '0;

            phase          <= PH_PAPER;
            tick_cnt       <= 32'd0;
            sec_left       <= 4'd0;

            total_sec      <= 8'd1;
            elapsed_sec    <= 8'd0;
            brew_progress16<= 5'd0;

            ing_err_latch  <= 16'd0;
            ing_tick_cnt   <= 32'd0;
            ing_secs_left  <= 4'd0;

        end else begin
            // Ingredient error latch behavior (only meaningful in SELECT)
            if (sys_error_condition) begin
                ing_err_latch <= 16'd0;
                ing_tick_cnt  <= 32'd0;
                ing_secs_left <= 4'd0;
            end else if (state != S_SELECT) begin
                ing_err_latch <= 16'd0;
                ing_tick_cnt  <= 32'd0;
                ing_secs_left <= 4'd0;
            end else begin
                if (bf_p || bt_p || bs_p) begin
                    ing_err_latch <= 16'd0;
                    ing_tick_cnt  <= 32'd0;
                    ing_secs_left <= 4'd0;
                end else if (ing_err_latch != 16'd0) begin
                    if (ing_secs_left == 4'd0) begin
                        ing_err_latch <= 16'd0;
                        ing_tick_cnt  <= 32'd0;
                    end else begin
                        if (ing_tick_cnt == (TICKS_PER_SEC-1)) begin
                            ing_tick_cnt <= 32'd0;
                            if (ing_secs_left <= 4'd1) begin
                                ing_err_latch <= 16'd0;
                                ing_secs_left <= 4'd0;
                            end else begin
                                ing_secs_left <= ing_secs_left - 4'd1;
                            end
                        end else begin
                            ing_tick_cnt <= ing_tick_cnt + 32'd1;
                        end
                    end
                end else begin
                    ing_tick_cnt  <= 32'd0;
                    ing_secs_left <= 4'd0;
                end
            end

            // System errors: force idle + stop timing (do NOT change selections)
            if (sys_error_condition) begin
                state           <= S_SELECT;
                phase           <= PH_PAPER;
                tick_cnt        <= 32'd0;
                sec_left        <= 4'd0;
                elapsed_sec     <= 8'd0;
                brew_progress16 <= 5'd0;
            end else begin
                // Selection changes only when idle/selecting
                if (state == S_SELECT) begin
                    if (bf_p) flavor <= ~flavor;
                    if (bt_p) dType  <= (dType == 3'd4) ? 3'd0 : (dType + 3'd1);
                    if (bs_p) dSize  <= (dSize == 2'd2) ? 2'd0 : (dSize + 2'd1);
                end

                case (state)
                    S_SELECT: begin
                        if (bstart_p) begin
                            if (ing_fail_mask != 16'b0) begin
                                ing_err_latch <= ing_fail_mask;
                                ing_tick_cnt  <= 32'd0;
                                ing_secs_left <= ING_ERR_HOLD_SECS[3:0];

                                elapsed_sec      <= 8'd0;
                                brew_progress16  <= 5'd0;
                                phase            <= PH_PAPER;
                                sec_left         <= 4'd0;
                                tick_cnt         <= 32'd0;
                            end else begin
                                // SUCCESSFUL START: latch selections + recipe
                                flavor_run <= flavor;
                                dType_run  <= dType;
                                dSize_run  <= dSize;

                                recipe_lat      <= recipe_live;
                                total_sec       <= calc_total_seconds(recipe_live);
                                elapsed_sec     <= 8'd0;
                                brew_progress16 <= 5'd0;

                                phase           <= PH_PAPER;
                                sec_left        <= 4'd0;
                                tick_cnt        <= 32'd0;

                                ing_err_latch   <= 16'd0;
                                ing_tick_cnt    <= 32'd0;
                                ing_secs_left   <= 4'd0;

                                state           <= S_WAIT;
                            end
                        end
                    end

                    S_WAIT: begin
                        if (W_TEMP == 1'b1) begin
                            state       <= S_BREW;
                            tick_cnt    <= 32'd0;
                            elapsed_sec <= 8'd0;
                            brew_progress16 <= 5'd0;

                            begin
                                phase_t p0;
                                p0      = first_nonzero_phase(PH_PAPER);
                                phase   <= p0;
                                sec_left<= phase_duration(p0);
                            end
                        end
                    end

                    S_BREW: begin
                        if (phase == PH_DONE) begin
                            state           <= S_SELECT;
                            phase           <= PH_PAPER;
                            tick_cnt        <= 32'd0;
                            sec_left        <= 4'd0;
                            elapsed_sec     <= total_sec;
                            brew_progress16 <= 5'd16;
                        end else begin
                            if (tick_cnt == (TICKS_PER_SEC-1)) begin
                                tick_cnt <= 32'd0;

                                if (elapsed_sec < total_sec)
                                    elapsed_sec <= elapsed_sec + 8'd1;

                                brew_progress16 <= calc_progress16(
                                    (elapsed_sec < total_sec) ? (elapsed_sec + 8'd1) : elapsed_sec,
                                    total_sec
                                );

                                if (sec_left != 4'd0)
                                    sec_left <= sec_left - 4'd1;

                                if (sec_left == 4'd1) begin
                                    phase_t p1;
                                    p1      = first_nonzero_phase(next_phase(phase));
                                    phase   <= p1;
                                    sec_left<= phase_duration(p1);
                                end

                            end else begin
                                tick_cnt <= tick_cnt + 32'd1;
                            end
                        end
                    end

                    default: state <= S_SELECT;
                endcase
            end
        end
    end

    //============================================================
    // Output logic
    //============================================================
    always_comb begin
        HEAT_EN      = 1'b0;
        POUROVER_EN  = 1'b0;
        WATER_EN     = 1'b0;
        GRINDER_0_EN = 1'b0;
        GRINDER_1_EN = 1'b0;
        PAPER_EN     = 1'b0;
        COCOA_EN     = 1'b0;
        CREAMER_EN   = 1'b0;

        if (!sys_error_condition) begin
            if ((state != S_SELECT) && (W_TEMP == 1'b0))
                HEAT_EN = 1'b1;

            if (state == S_BREW) begin
                if (sec_left != 4'd0) begin
                    case (phase)
                        PH_PAPER: PAPER_EN = 1'b1;

                        PH_GRIND: begin
                            if (flavor_run == 1'b0) GRINDER_0_EN = 1'b1;
                            else                    GRINDER_1_EN = 1'b1;
                        end

                        PH_COCOA: COCOA_EN = 1'b1;
                        PH_POUR:  POUROVER_EN = 1'b1;
                        PH_WATER: WATER_EN = 1'b1;
                        default: ;
                    endcase
                end

                if (r_add_creamer)
                    CREAMER_EN = 1'b1;
            end
        end
    end

endmodule
