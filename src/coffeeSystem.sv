//======================== coffeeSystem.sv ========================
`timescale 1ns/1ps
`include "cmach_recipes.svh"

module coffeeSystem #(
    parameter int CLK_HZ      = 50_000_000,
    parameter int SPEEDUP_DIV  = 1          // set >1 to speed simulation
) (
    input  logic        clk,
    input  logic        rst,

    // UI pushbuttons (level signals; module edge-detects them)
    input  logic        btn_flavor,
    input  logic        btn_type,
    input  logic        btn_size,
    input  logic        btn_start,

    // Sensors
    input  logic [1:0]  PAPER_LEVEL,
    input  logic        BIN_0_AMPTY,
    input  logic        BIN_1_AMPTY,
    input  logic        ND_AMPTY,
    input  logic        CH_AMPTY,
    input  logic [1:0]  W_PRESSURE,
    input  logic        W_TEMP,
    input  logic        STATUS,

    // Recipe table (15 entries) (packed bits, matches your cmach_recp output)
    input  logic [$bits(coffee_recipe_t)-1:0] recipes [0:14],

    // Current selections (for LCD display)
    output logic        cur_flavor,     // 0=Coffee1, 1=Coffee2
    output logic [2:0]  cur_type,       // 0..4
    output logic [1:0]  cur_size,       // 0..2

    // State visibility (for LCD display)
    output logic [1:0]  sys_state,      // 0=SELECT, 1=WAITING(HEAT), 2=BREWING

    // Motor/control outputs
    output logic        HEAT_EN,
    output logic        POUROVER_EN,
    output logic        WATER_EN,
    output logic        GRINDER_0_EN,
    output logic        GRINDER_1_EN,
    output logic        PAPER_EN,

    // Optional extras
    output logic        COCOA_EN,
    output logic        CREAMER_EN,

    // NEW: selection/system error bitmask (for LCD cycling + start-blocking)
    output logic [15:0] err_mask,

    // NEW: brewing phase + progress (for LCD progress bar)
    output logic [2:0]  brew_phase,
    output logic [4:0]  brew_progress16   // 0..16
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
    //============================================================
    logic bf_d, bt_d, bs_d, bstart_d;
    logic bf_p, bt_p, bs_p, bstart_p;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bf_d     <= 1'b0; bt_d     <= 1'b0; bs_d     <= 1'b0; bstart_d <= 1'b0;
        end else begin
            bf_d     <= btn_flavor;
            bt_d     <= btn_type;
            bs_d     <= btn_size;
            bstart_d <= btn_start;
        end
    end

    assign bf_p     = btn_flavor & ~bf_d;
    assign bt_p     = btn_type   & ~bt_d;
    assign bs_p     = btn_size   & ~bs_d;
    assign bstart_p = btn_start  & ~bstart_d;

    //============================================================
    // Top-level state machine
    //============================================================
    typedef enum logic [1:0] { S_SELECT=2'd0, S_WAIT=2'd1, S_BREW=2'd2 } state_t;
    state_t state;

    // Selections (only change in S_SELECT)
    logic flavor;
    logic [2:0] dType;
    logic [1:0] dSize;

    assign cur_flavor = flavor;
    assign cur_type   = dType;
    assign cur_size   = dSize;
    assign sys_state  = state;

    //============================================================
    // Recipe lookup (index = type*3 + size) 0..14
    //============================================================
    logic [3:0] rIndex;
    coffee_recipe_t recipe_live;

    always_comb begin
        // keep this strictly 4-bit (avoids truncation warnings)
        rIndex      = ( {1'b0,dType} * 4'd3 ) + {2'b0,dSize};
        recipe_live = coffee_recipe_t'(recipes[rIndex]);
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

    // Also unpack live recipe for selection validity checks
    logic       lv_load_filter, lv_add_creamer;
    logic [3:0] lv_pour_time, lv_hot_water_time, lv_grinder_time, lv_cocoa_time;
    logic       lv_unused_HP;

    always_comb begin
        {lv_load_filter, lv_unused_HP, lv_pour_time, lv_hot_water_time,
         lv_grinder_time, lv_cocoa_time, lv_add_creamer} = recipe_live;
    end

    //============================================================
    // Selection/system invalid condition => err_mask (continuous)
    //============================================================
    always_comb begin
        err_mask = 16'b0;

        // Paper errors
        if (PAPER_LEVEL == 2'b00) err_mask[E_PAPER_NOT_INST] = 1'b1;
        else if (PAPER_LEVEL == 2'b01) err_mask[E_PAPER_EMPTY] = 1'b1;

        // Water pressure errors
        if (W_PRESSURE == 2'b11) err_mask[E_PRESS_ERR] = 1'b1;
        else if (W_PRESSURE == 2'b10) err_mask[E_PRESS_HIGH] = 1'b1;

        // Hardware status error
        if (STATUS == 1'b0) err_mask[E_STATUS_ERR] = 1'b1;

        // Coffee needed? (only if grinder_time != 0)
        if (lv_grinder_time != 4'd0) begin
            if (!flavor && BIN_0_AMPTY) err_mask[E_NO_COFFEE0] = 1'b1;
            if ( flavor && BIN_1_AMPTY) err_mask[E_NO_COFFEE1] = 1'b1;
        end

        // Chocolate needed? (only if cocoa_time != 0)
        if ((lv_cocoa_time != 4'd0) && CH_AMPTY) err_mask[E_NO_CHOC] = 1'b1;

        // Creamer needed? (only if recipe requests it)
        if (lv_add_creamer && ND_AMPTY) err_mask[E_NO_CREAMER] = 1'b1;
    end

    wire error_condition = |err_mask;

    //============================================================
    // Brewing phase machine (timed steps)
    //============================================================
    typedef enum logic [2:0] {
        PH_PAPER=3'd0, PH_GRIND=3'd1, PH_COCOA=3'd2, PH_POUR=3'd3, PH_WATER=3'd4, PH_DONE=3'd5
    } phase_t;

    phase_t phase;

    assign brew_phase = phase;

    localparam int TICKS_PER_SEC = (CLK_HZ / SPEEDUP_DIV);

    logic [31:0] tick_cnt;
    logic [3:0]  sec_left;

    function automatic [3:0] phase_duration(input phase_t p);
        begin
            case (p)
                PH_PAPER: phase_duration = (r_load_filter) ? 4'd1 : 4'd0;  // 1s if required
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

    // Synthesis-safe "skip zero-duration phases" (bounded loop)
    function automatic phase_t first_nonzero_phase(input phase_t start_p);
        phase_t p;
        int k;
        begin
            p = start_p;
            for (k = 0; k < 6; k++) begin
                if (p == PH_DONE) begin
                    // keep PH_DONE
                end else if (phase_duration(p) != 4'd0) begin
                    // keep p
                end else begin
                    p = next_phase(p);
                end
            end
            first_nonzero_phase = p;
        end
    endfunction

    //============================================================
    // Progress (0..16) across all recipe steps (BREW only)
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

            recipe_lat     <= '0;

            phase          <= PH_PAPER;
            tick_cnt       <= 32'd0;
            sec_left       <= 4'd0;

            total_sec      <= 8'd1;
            elapsed_sec    <= 8'd0;
            brew_progress16<= 5'd0;

        end else begin
            // Any error => force idle + stop timing
            if (error_condition) begin
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
                            // If selection invalid, do not start (LCD will show cycling err)
                            if (!error_condition) begin
                                recipe_lat      <= recipe_live;
                                total_sec       <= calc_total_seconds(recipe_live);
                                elapsed_sec     <= 8'd0;
                                brew_progress16 <= 5'd0;

                                phase           <= PH_PAPER;
                                sec_left        <= 4'd0;
                                tick_cnt        <= 32'd0;

                                state           <= S_WAIT;
                            end
                        end
                    end

                    S_WAIT: begin
                        // Wait until hot water ready
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

                                // advance total progress each second during brew
                                if (elapsed_sec < total_sec)
                                    elapsed_sec <= elapsed_sec + 8'd1;

                                brew_progress16 <= calc_progress16(
                                    (elapsed_sec < total_sec) ? (elapsed_sec + 8'd1) : elapsed_sec,
                                    total_sec
                                );

                                // phase countdown
                                if (sec_left != 4'd0)
                                    sec_left <= sec_left - 4'd1;

                                // phase transition when this second finishes the phase
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

        if (!error_condition) begin
            // Heater while waiting/brewing and water is not hot
            if ((state != S_SELECT) && (W_TEMP == 1'b0))
                HEAT_EN = 1'b1;

            if (state == S_BREW) begin
                if (sec_left != 4'd0) begin
                    case (phase)
                        PH_PAPER: PAPER_EN = 1'b1;

                        PH_GRIND: begin
                            if (flavor == 1'b0) GRINDER_0_EN = 1'b1;
                            else                GRINDER_1_EN = 1'b1;
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
