`timescale 1ns/1ps

module lcdIp_tb;

    // DUT signals
    reg clk, reset, send;
    reg [2:0] userCommand0;
    wire [7:0] lcd_data;
    wire lcd_rs, lcd_rw, lcd_e;
    wire busy, systemReady;

    // instantiate DUT
    lcdIp uut (
        .clk(clk),
        .userCommand0(userCommand0),
        .send(send),
        .reset(reset),
        .lcd_data(lcd_data),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_e(lcd_e),
        .busy(busy),
        .systemReady(systemReady)
    );

    // 100 MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // command encoding
    localparam SET_CURSOR = 3'b001;
    localparam WRITE_CHAR = 3'b010;
    localparam CLEAR      = 3'b110;

    // LCD codes (HD44780-style, not ASCII)
    reg [7:0] lcdCodes [0:10];
    integer i;

    initial begin
        // fill message: “HELLO WORLD”
        lcdCodes[0]  = 8'h48; // H
        lcdCodes[1]  = 8'h45; // E
        lcdCodes[2]  = 8'h4C; // L
        lcdCodes[3]  = 8'h4C; // L
        lcdCodes[4]  = 8'h4F; // O
        lcdCodes[5]  = 8'h20; // space
        lcdCodes[6]  = 8'h57; // W
        lcdCodes[7]  = 8'h4F; // O
        lcdCodes[8]  = 8'h52; // R
        lcdCodes[9]  = 8'h4C; // L
        lcdCodes[10] = 8'h44; // D

        $display("\n=== LCD TEXT SIMULATION START ===");

        // reset
        reset = 1; send = 0; userCommand0 = 3'b000;
        #50; reset = 0; #50;

        // clear screen
        $display("[TB] CLEAR display");
        userCommand0 = CLEAR; send = 1; #10; send = 0;
        repeat(1000) @(posedge clk);

        // set cursor
        $display("[TB] SET cursor to 0x80");
        userCommand0 = SET_CURSOR; send = 1; #10; send = 0;
        repeat(1000) @(posedge clk);

        // write each LCD code
        for (i = 0; i < 11; i = i + 1) begin
            userCommand0 = WRITE_CHAR;
            send = 1; #10; send = 0;
            // print character as it’s sent
            $display("[LCD] RS=%b RW=%b E=%b DATA=0x%02h (%s)",
                     uut.lcd_rs, uut.lcd_rw, uut.lcd_e,
                     lcdCodes[i],
                     (lcdCodes[i] >= 8'h20 && lcdCodes[i] <= 8'h7E) ?
                        {lcdCodes[i]} : "?");
            repeat(1000) @(posedge clk);
        end

        $display("\n=== LCD SIMULATION COMPLETE ===\n");
        $finish;
    end

endmodule
