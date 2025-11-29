module sync(
	input swIn,
	input clk,
	output syncSignal
	);

// Flip flop registers
reg ff1;
reg ff2;
	
// Non-blocking assignments to flip flops, sync output signal to the end of flip flop 2
always@(posedge clk) begin
	 ff1 <= swIn;
	 ff2 <= ff1;
end
	
assign syncSignal = ff2;
endmodule
