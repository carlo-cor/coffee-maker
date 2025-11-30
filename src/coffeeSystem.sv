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

    // Recipe table (15 entries)
    input  coffee_recipe_t recipes [0:14],

    // Current selections (for LCD display)
    output logic        cur_flavor,     // 0=Coffee1, 1=Coffee2
    output logic [2:0]  cur_type,       // 0..4
    output logic [1:0]  cur_size,       // 0..2

    // State visibility (for LCD display)
    output logic [1:0]  sys_state,      // 0=SELECT, 1=WAITING, 2=BREWING

    // Motor/control outputs
    output logic        HEAT_EN,
    output logic        POUROVER_EN,
    output logic        WATER_EN,
    output logic        GRINDER_0_EN,
    output logic        GRINDER_1_EN,
    output logic        PAPER_EN,

    // Optional extras (safe to ignore if unused)
    output logic        COCOA_EN,
    output logic        CREAMER_EN
);

    //========================================
    // Edge-detect buttons (one action per press)
    //========================================
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

    //========================================
    // Error condition (forces idle / disables brewing)
    //========================================
    logic error_condition;
    always_comb begin
        error_condition = 1'b0;

        // PAPER: 00 not installed (Error), 01 empty (Error)
        if (PAPER_LEVEL == 2'b00) error_condition = 1'b1;
        else if (PAPER_LEVEL == 2'b01) error_condition = 1'b1;

        // W_PRESSURE: 11 error (Error), 10 high (Error)
        else if (W_PRESSURE == 2'b11) error_condition = 1'b1;
        else if (W_PRESSURE == 2'b10) error_condition = 1'b1;

        // STATUS: 0 error (Error)
        else if (STATUS == 1'b0) error_condition = 1'b1;
    end

    //========================================
    // Top-level state machine (Selection / Waiting / Brewing)
    //========================================
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

    // Recipe lookup (index = type*3 + size)
    logic [3:0] rIndex;
    coffee_recipe_t recipe_live;

    always_comb begin
        rIndex      = (dType * 3) + dSize;
        recipe_live = recipes[rIndex];
    end

    // Latch recipe when starting (so it cannot change mid-brew)
    coffee_recipe_t recipe_lat;

    // Unpack recipe latched fields (positional, avoids needing struct field names)
    logic       r_load_filter, r_high_press, r_add_creamer;
    logic [3:0] r_pour_time, r_hot_water_time, r_grinder_time, r_cocoa_time;

    always_comb begin
        {r_load_filter, r_high_press, r_pour_time, r_hot_water_time,
         r_grinder_time, r_cocoa_time, r_add_creamer} = recipe_lat;
    end

    //========================================
    // Brewing phase machine (timed steps)
    //========================================
    typedef enum logic [2:0] { PH_PAPER=3'd0, PH_GRIND=3'd1, PH_COCOA=3'd2, PH_POUR=3'd3, PH_WATER=3'd4, PH_DONE=3'd5 } phase_t;
    phase_t phase;

    localparam int TICKS_PER_SEC = (CLK_HZ / SPEEDUP_DIV);

    logic [31:0] tick_cnt;
    logic [3:0]  sec_left;

    function automatic [3:0] phase_duration(phase_t p);
        begin
            case (p)
                PH_PAPER: phase_duration = (r_load_filter) ? 4'd1 : 4'd0;  // fixed 1s if required
                PH_GRIND: phase_duration = r_grinder_time;
                PH_COCOA: phase_duration = r_cocoa_time;
                PH_POUR:  phase_duration = r_pour_time;
                PH_WATER: phase_duration = r_hot_water_time;
                default:  phase_duration = 4'd0;
            endcase
        end
    endfunction

    function automatic phase_t next_phase(phase_t p);
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

    task automatic start_next_nonzero_phase;
        phase_t p;
        begin
            p = phase;
            // advance until a phase with nonzero duration or DONE
            while ((p != PH_DONE) && (phase_duration(p) == 4'd0)) begin
                p = next_phase(p);
            end
            phase    = p;
            sec_left = phase_duration(p);
            tick_cnt = 32'd0;
        end
    endtask

    //========================================
    // State + selection + brew timing
    //========================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_SELECT;

            flavor     <= 1'b0;
            dType      <= 3'd0;
            dSize      <= 2'd0;

            recipe_lat <= '0;

            phase      <= PH_PAPER;
            tick_cnt   <= 32'd0;
            sec_left   <= 4'd0;
        end else begin
            // If an error occurs, force idle and stop outputs (LCD will show error via top)
            if (error_condition) begin
                state    <= S_SELECT;
                phase    <= PH_PAPER;
                tick_cnt <= 32'd0;
                sec_left <= 4'd0;
            end else begin
                // Selection changes only when idle/selecting
                if (state == S_SELECT) begin
                    if (bf_p) flavor <= ~flavor;
                    if (bt_p) dType  <= (dType == 3'd4) ? 3'd0 : (dType + 3'd1);
                    if (bs_p) dSize  <= (dSize == 2'd2) ? 2'd0 : (dSize + 2'd1);
                end

                case (state)
                    S_SELECT: begin
                        // start brew process (locks selections because state changes)
                        if (bstart_p) begin
                            recipe_lat <= recipe_live;
                            phase      <= PH_PAPER;
                            sec_left   <= 4'd0;
                            tick_cnt   <= 32'd0;
                            state      <= S_WAIT;
                        end
                    end

                    S_WAIT: begin
                        // Wait for hot water, then begin phased brew
                        if (W_TEMP == 1'b1) begin
                            state    <= S_BREW;

                            phase    <= PH_PAPER;
                            sec_left <= 4'd0;
                            tick_cnt <= 32'd0;

                            // initialize to first non-zero phase
                            start_next_nonzero_phase();
                        end
                    end

                    S_BREW: begin
                        if (phase == PH_DONE) begin
                            state    <= S_SELECT;
                            phase    <= PH_PAPER;
                            tick_cnt <= 32'd0;
                            sec_left <= 4'd0;
                        end else begin
                            // run 1-second ticks
                            if (tick_cnt == (TICKS_PER_SEC-1)) begin
                                tick_cnt <= 32'd0;

                                if (sec_left != 4'd0)
                                    sec_left <= sec_left - 4'd1;

                                // If that just hit 0, advance to next phase
                                if (sec_left == 4'd1) begin
                                    phase <= next_phase(phase);
                                    // load next phase duration (and skip zeros)
                                    start_next_nonzero_phase();
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

    //========================================
    // Output logic (all disabled unless actively waiting/brewing)
    //========================================
    always_comb begin
        // defaults
        HEAT_EN     = 1'b0;
        POUROVER_EN = 1'b0;
        WATER_EN    = 1'b0;
        GRINDER_0_EN= 1'b0;
        GRINDER_1_EN= 1'b0;
        PAPER_EN    = 1'b0;
        COCOA_EN    = 1'b0;
        CREAMER_EN  = 1'b0;

        if (!error_condition) begin
            // Heater only when water is cold, and only during an active process
            if ((state != S_SELECT) && (W_TEMP == 1'b0))
                HEAT_EN = 1'b1;

            if (state == S_BREW) begin
                // enable per phase (only while there is time left)
                if (sec_left != 4'd0) begin
                    case (phase)
                        PH_PAPER: begin
                            PAPER_EN = 1'b1;
                        end
                        PH_GRIND: begin
                            if (flavor == 1'b0) GRINDER_0_EN = 1'b1;
                            else                GRINDER_1_EN = 1'b1;
                        end
                        PH_COCOA: begin
                            COCOA_EN = 1'b1;
                        end
                        PH_POUR: begin
                            POUROVER_EN = 1'b1;
                        end
                        PH_WATER: begin
                            WATER_EN = 1'b1;
                        end
                        default: ;
                    endcase
                end

                if (r_add_creamer) begin
                    // simple behavior: keep asserted during brew; you can refine later
                    CREAMER_EN = 1'b1;
                end
            end
        end
    end

endmodule
