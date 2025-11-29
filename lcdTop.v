module lcdTop (
    input  wire clk,
    input  wire rst_n,          // KEY[0], active-low
    output wire [7:0] lcd_data,
    output wire lcd_rs,
    output wire lcd_rw,
    output wire lcd_e,
    output wire lcd_on
);

    // --------------------------------------------
    // Internal signals
    // --------------------------------------------
    wire rst = ~rst_n;          // active-high internal reset
    reg  [7:0] inputChar;
    reg        send;
    wire       systemReady;
    reg  [23:0] delayCounter;
    reg  [3:0]  index;
    reg         sent;

    assign lcd_on = 1'b1;       // turn LCD power ON always

    // --------------------------------------------
    // Instantiate LCD driver
    // --------------------------------------------
    lcdIp lcd0 (
        .clk(clk),
        .rst(rst),
        .inputString(inputChar),
        .send(send),
        .lcd_data(lcd_data),
        .lcd_rs(lcd_rs),
        .lcd_rw(lcd_rw),
        .lcd_e(lcd_e),
        .systemReady(systemReady)
    );

    // --------------------------------------------
    // Message buffer (constant at compile-time)
    // --------------------------------------------
    // *** CHANGED: use 'initial' instead of 'always @(*)'
    // This makes the array a fixed ROM-style constant.
    reg [7:0] message [0:10];
    initial begin
        message[0]  = "H";
        message[1]  = "E";
        message[2]  = "L";
        message[3]  = "L";
        message[4]  = "O";
        message[5]  = " ";
        message[6]  = "W";
        message[7]  = "O";
        message[8]  = "R";
        message[9]  = "L";
        message[10] = "D";
    end

    // --------------------------------------------
    // Sequencer: send one char every 50 ms
    // --------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            delayCounter <= 0;
            index        <= 0;
            send         <= 0;
            inputChar    <= 8'h00;
            sent         <= 0;
        end else begin
            if (systemReady && !sent) begin
                delayCounter <= delayCounter + 1;

                // 50 ms interval (2.5 M cycles @ 50 MHz)
                if (delayCounter >= 24'd2_500_000) begin
                    inputChar <= message[index];
                    send <= 1;
                    delayCounter <= 0;
                    index <= index + 1;
                    if (index == 11)
                        sent <= 1;
                end else begin
                    send <= 0;
                end
            end else begin
                send <= 0;
            end
        end
    end
endmodule
