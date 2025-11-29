module lcdIp_Top (
    // Clock and Active-Low Reset
    input  wire        CLOCK_50,
    input  wire        KEY,            
     
    // Sensor Inputs
    input  wire [1:0]  PAPER_LEVEL,
    input  wire        BIN_0_AMPTY,
    input  wire        BIN_1_AMPTY,
    input  wire        ND_AMPTY,
    input  wire        CH_AMPTY,
    input  wire [1:0]  W_PRESSURE,
    input  wire        W_TEMP,
    
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

    // Command Interface to lcdIp
    reg  [1:0] op;         // 2'b00 = INSTR (RS=0), 2'b01 = DATA (RS=1)
    reg        send;
    reg        rst;
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

    // FIXED: Simple synchronous reset
    always @(posedge CLOCK_50) begin
        rst <= ~KEY;
    end

    // --- Two-line message ROMs (16 chars per line) ---
    reg [7:0] m0_l1 [0:15] = '{"P","l","e","a","s","e"," ","O","r","d","e","r"," ","a"," "," "};
    reg [7:0] m0_l2 [0:15] = '{"c","o","f","f","e","e"," "," "," "," "," "," "," "," "," "," "};
    reg [7:0] m1_l1 [0:15] = '{"P","a","p","e","r"," ","F","i","l","t","e","r"," ","A","l","m"};
    reg [7:0] m1_l2 [0:15] = '{"s","t"," ","E","m","p","t","y"," "," "," "," "," "," "," "," "};
    reg [7:0] m2_l1 [0:15] = '{"P","a","p","e","r"," ","F","i","l","t","e","r"," "," "," "," "};
    reg [7:0] m2_l2 [0:15] = '{"E","m","p","t","y"," "," "," "," "," "," "," "," "," "," "," "};
    reg [7:0] m3_l1 [0:15] = '{"P","a","p","e","r"," ","F","i","l","t","e","r"," ","N","O","T"};
    reg [7:0] m3_l2 [0:15] = '{"I","N","S","T","A","L","L","E","D"," "," "," "," "," "," "," "};
    reg [7:0] m4_l1 [0:15] = '{"C","o","f","f","e","e"," ","B","i","n"," ","0"," ","A","l","m"};
    reg [7:0] m4_l2 [0:15] = '{"s","t"," ","E","m","p","t","y"," "," "," "," "," "," "," "," "};
    reg [7:0] m5_l1 [0:15] = '{"C","o","f","f","e","e"," ","B","i","n"," ","1"," ","A","l","m"};
    reg [7:0] m5_l2 [0:15] = '{"s","t"," ","E","m","p","t","y"," "," "," "," "," "," "," "," "};
    reg [7:0] m6_l1 [0:15] = '{"N","o","n","-","D","a","i","r","y"," ","C","r","m","r"," ","A"};
    reg [7:0] m6_l2 [0:15] = '{"l","m","s","t"," ","E","m","p","t","y"," "," "," "," "," "," "};
    reg [7:0] m7_l1 [0:15] = '{"C","h","o","c","o","l","a","t","e"," ","P","w","d","r"," ","A"};
    reg [7:0] m7_l2 [0:15] = '{"l","m","s","t"," ","E","m","p","t","y"," "," "," "," "," "," "};
    reg [7:0] m8_l1 [0:15] = '{"W","a","t","e","r"," ","P","r","e","s","s","u","r","e"," "," "};
    reg [7:0] m8_l2 [0:15] = '{"E","r","r","o","r","!"," "," "," "," "," "," "," "," "," "," "};
    reg [7:0] m9_l1 [0:15] = '{"H","i","g","h"," ","W","a","t","e","r"," "," "," "," "," "," "};
    reg [7:0] m9_l2 [0:15] = '{"P","r","e","s","s","u","r","e"," "," "," "," "," "," "," "," "};
    reg [7:0] m10_l1 [0:15] = '{"L","o","w"," ","W","a","t","e","r"," "," "," "," "," "," "," "};
    reg [7:0] m10_l2 [0:15] = '{"P","r","e","s","s","u","r","e"," "," "," "," "," "," "," "," "};

    // FIXED: Error message selection logic - SIMPLIFIED AND DEBUGGABLE
    reg [3:0] error_sel;
    always @(*) begin
        error_sel = 4'd0; // Default to normal message
        
        // Check each condition explicitly with priority
        if (PAPER_LEVEL == 2'b00) begin
			error_sel = 4'd3; // "Paper Filter NOT INSTALLED"
        end
        else if (PAPER_LEVEL == 2'b01) begin  
            error_sel = 4'd2; // "Paper Filter Empty"
        end
        else if (PAPER_LEVEL == 2'b10) begin  
            error_sel = 4'd1; // "Paper Filter Almost Empty"
        end
        else if (W_PRESSURE == 2'b11) begin   
            error_sel = 4'd8; // "Water Pressure Error!"
        end
        else if (W_PRESSURE == 2'b10) begin   
            error_sel = 4'd9; // "High Water Pressure"
        end
        else if (W_PRESSURE == 2'b00) begin   
            error_sel = 4'd10; // "Low Water Pressure"
        end
        else if (BIN_0_AMPTY) begin           
            error_sel = 4'd4; // "Coffee Bin 0 Almost Empty"
        end
        else if (BIN_1_AMPTY) begin           
            error_sel = 4'd5; // "Coffee Bin 1 Almost Empty"
        end
        else if (ND_AMPTY) begin              
            error_sel = 4'd6; // "Non-Dairy Creamer Almost Empty"
        end
        else if (CH_AMPTY) begin              
            error_sel = 4'd7; // "Chocolate Powder Almost Empty"
        end
    end

    // FIXED: Add comprehensive debug outputs
    wire [3:0] debug_error_sel = error_sel;
    wire debug_paper_empty = (PAPER_LEVEL == 2'b01);
    wire [1:0] debug_paper_level = PAPER_LEVEL;
    wire [1:0] debug_w_pressure = W_PRESSURE;

    // FSM states
    localparam [5:0]
        S_PWRUP     = 6'd0,
        S_INIT1     = 6'd1,   S_WAIT1   = 6'd2,
        S_INIT2     = 6'd3,   S_WAIT2   = 6'd4,
        S_INIT3     = 6'd5,   S_WAIT3   = 6'd6,
        S_FUNCSET   = 6'd7,   S_WAIT_DISPOFF   = 6'd8,
        S_DISPOFF   = 6'd9,   S_WAIT_CLR   = 6'd10,
        S_CLEAR     = 6'd11,  S_WAIT_ENTRY   = 6'd12,
        S_ENTRY     = 6'd13,  S_WAIT_DISPON   = 6'd14,
        S_DISPON    = 6'd15,  S_WAITON  = 6'd16,
        S_SET_L1    = 6'd17,  S_WAIT_L1 = 6'd18,
        S_WRITE_L1  = 6'd19,  S_WAIT_WL1= 6'd20,
        S_SET_L2    = 6'd21,  S_WAIT_L2 = 6'd22,
        S_WRITE_L2  = 6'd23,  S_WAIT_WL2= 6'd24,
        S_IDLE      = 6'd25,
        S_CLR_SW    = 6'd26,  S_WAIT_ENTRY_SW= 6'd27;

    reg [5:0]  state = S_PWRUP;
    reg [31:0] dly = 0;
    reg [4:0]  idx = 0;
    reg [3:0]  cur_sel = 4'd0;

    // 50 MHz delays
    localparam DLY_15MS   = 32'd750_000;
    localparam DLY_5MS    = 32'd250_000;
    localparam DLY_100US  = 32'd5_000;
    localparam DLY_CMD    = 32'd5_000;
    localparam DLY_CLEAR  = 32'd75_000;

    // Helper Function: pick correct ROM byte based on message selection
    function automatic [7:0] get_byte;
        input [3:0] msg_sel;
        input line;
        input [4:0] k;
        begin
            case(msg_sel)
                4'd0: get_byte = line ? m0_l2[k] : m0_l1[k];
                4'd1: get_byte = line ? m1_l2[k] : m1_l1[k];
                4'd2: get_byte = line ? m2_l2[k] : m2_l1[k];
                4'd3: get_byte = line ? m3_l2[k] : m3_l1[k];
                4'd4: get_byte = line ? m4_l2[k] : m4_l1[k];
                4'd5: get_byte = line ? m5_l2[k] : m5_l1[k];
                4'd6: get_byte = line ? m6_l2[k] : m6_l1[k];
                4'd7: get_byte = line ? m7_l2[k] : m7_l1[k];
                4'd8: get_byte = line ? m8_l2[k] : m8_l1[k];
                4'd9: get_byte = line ? m9_l2[k] : m9_l1[k];
                4'd10: get_byte = line ? m10_l2[k] : m10_l1[k];
                default: get_byte = line ? m0_l2[k] : m0_l1[k];
            endcase
        end
    endfunction

    // FIXED: Improved change detection
    reg [3:0] prev_error_sel;
    reg change_detected;
    
    always @(posedge CLOCK_50) begin
        if (rst) begin
            prev_error_sel <= 4'd0;
            change_detected <= 1'b0;
        end else begin
            // Always update previous value
            prev_error_sel <= error_sel;
            
            // Set change detected when values differ
            if (error_sel != prev_error_sel) begin
                change_detected <= 1'b1;
            end 
            // Clear change detected when we start processing the change
            else if (state == S_CLR_SW) begin
                change_detected <= 1'b0;
            end
        end
    end

    // FIXED: Main FSM with better state management
    always @(posedge CLOCK_50) begin
        if (rst) begin
            state   <= S_PWRUP;
            dly     <= 0;
            idx     <= 0;
            op      <= 2'b00;
            din     <= 8'h00;
            send    <= 1'b0;
            cur_sel <= 4'd0;
        end else begin
            send <= 1'b0; // Default to not sending

            case (state)
                // --- Initialization Sequence ---
                S_PWRUP: begin
                    if (dly < DLY_15MS) 
                        dly <= dly + 1;
                    else begin
                        din   <= 8'h30; 
                        op    <= 2'b00; 
                        send  <= 1'b1;
                        dly   <= 0; 
                        state <= S_WAIT1;
                    end
                end

                S_WAIT1: begin
                    if (!busy && dly >= DLY_5MS) begin
                        din   <= 8'h30; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT2;
                    end else 
                        dly <= dly + 1;
                end

                S_WAIT2: begin
                    if (!busy && dly >= DLY_100US) begin
                        din   <= 8'h30; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT3;
                    end else 
                        dly <= dly + 1;
                end

                S_WAIT3: begin
                    if (!busy && dly >= DLY_100US) begin
                        din   <= 8'h38; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_DISPOFF;
                    end else 
                        dly <= dly + 1;
                end

                S_WAIT_DISPOFF: begin
                    if (!busy && dly >= DLY_CMD) begin
                        din   <= 8'h08; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_CLR;
                    end else 
                        dly <= dly + 1;
                end

                S_WAIT_CLR: begin
                    if (!busy && dly >= DLY_CMD) begin
                        din   <= 8'h01; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_ENTRY;
                    end else 
                        dly <= dly + 1;
                end

                S_WAIT_ENTRY: begin
                    if (!busy && dly >= DLY_CLEAR) begin
                        din   <= 8'h06; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_DISPON;
                    end else 
                        dly <= dly + 1;
                end

                S_WAIT_DISPON: begin
                    if (!busy && dly >= DLY_CMD) begin
                        din   <= 8'h0C; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAITON;
                    end else 
                        dly <= dly + 1;
                end

                S_WAITON: begin
                    if (!busy && dly >= DLY_CMD) begin
                        cur_sel <= error_sel;
                        state   <= S_SET_L1;
                    end else 
                        dly <= dly + 1;
                end

                // --- Display Writing ---
                S_SET_L1: begin
                    if (!busy) begin
                        din   <= 8'h80; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        idx   <= 0; 
                        state <= S_WAIT_L1;
                    end
                end

                S_WAIT_L1: begin
                    if (!busy && dly >= DLY_CMD) begin
                        state <= S_WRITE_L1;
                    end else 
                        dly <= dly + 1;
                end

                S_WRITE_L1: begin
                    if (!busy) begin
                        din   <= get_byte(cur_sel, 1'b0, idx);
                        op    <= 2'b01; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_WL1;
                    end
                end

                S_WAIT_WL1: begin
                    if (!busy && dly >= DLY_CMD) begin
                        if (idx < 5'd15) begin
                            idx   <= idx + 1; 
                            state <= S_WRITE_L1;
                        end else begin
                            idx   <= 0; 
                            state <= S_SET_L2;
                        end
                    end else 
                        dly <= dly + 1;
                end

                S_SET_L2: begin
                    if (!busy) begin
                        din   <= 8'hC0; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_L2;
                    end
                end

                S_WAIT_L2: begin
                    if (!busy && dly >= DLY_CMD) begin
                        state <= S_WRITE_L2;
                    end else 
                        dly <= dly + 1;
                end

                S_WRITE_L2: begin
                    if (!busy) begin
                        din   <= get_byte(cur_sel, 1'b1, idx);
                        op    <= 2'b01; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_WL2;
                    end
                end

                S_WAIT_WL2: begin
                    if (!busy && dly >= DLY_CMD) begin
                        if (idx < 5'd15) begin
                            idx   <= idx + 1; 
                            state <= S_WRITE_L2;
                        end else begin
                            idx   <= 0; 
                            state <= S_IDLE;
                        end
                    end else 
                        dly <= dly + 1;
                end

                // --- Idle State: Monitor for Changes ---
                S_IDLE: begin
                    if (change_detected && !busy) begin
                        state <= S_CLR_SW;
                    end
                end

                S_CLR_SW: begin
                    if (!busy) begin
                        din   <= 8'h01; 
                        op    <= 2'b00; 
                        send  <= 1'b1; 
                        dly   <= 0; 
                        state <= S_WAIT_ENTRY_SW;
                    end
                end

                S_WAIT_ENTRY_SW: begin
                    if (!busy && dly >= DLY_CLEAR) begin
                        cur_sel <= error_sel;
                        state   <= S_SET_L1;
                    end else 
                        dly <= dly + 1;
                end

                default: state <= S_PWRUP;
            endcase
        end
    end
endmodule