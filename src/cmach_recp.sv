`timescale 1ns/1ps
`include "cmach_recipes.svh"

// Coffee recipe table: 5 drinks (Mocha, Latte, Espresso, Americano, Drip)
// each in 3 sizes (Small, Medium, Large) => 15 entries total.
module cmach_recp;

	// Drinks enumeration (indices)
	typedef enum int { MOCHA=0, LATTE=1, ESPRESSO=2, AMERICANO=3, DRIP=4 } drink_e;
	// size indices
	localparam int SIZE_S = 0;
	localparam int SIZE_M = 1;
	localparam int SIZE_L = 2;

	localparam int NUM_DRINKS = 5;
	localparam int NUM_SIZES  = 3;
	localparam int NUM_RECIPES = NUM_DRINKS * NUM_SIZES;

	// helper to compute recipe index from drink and size
	function automatic int ridx(input drink_e d, input int size_idx);
		ridx = d * NUM_SIZES + size_idx;
	endfunction

	// Recipe array
	coffee_recipe_t recipes [0:NUM_RECIPES-1];

	// Small helper to build a recipe value (keeps initial block concise)
	function automatic coffee_recipe_t set_recipe(
		input logic load_filter_in,
		input logic high_press_in,
		input logic [3:0] pour_time_in,
		input logic [3:0] hot_water_time_in,
		input logic [3:0] grinder_time_in,
		input logic [3:0] cocoa_time_in,
		input logic add_creamer_in
	);
		set_recipe = '{load_filter_in, high_press_in, pour_time_in, hot_water_time_in, grinder_time_in, cocoa_time_in, add_creamer_in};
	endfunction

	// Named localparams for convenient indexing
	localparam int MOCHA_S     = ridx(MOCHA, SIZE_S);
	localparam int MOCHA_M     = ridx(MOCHA, SIZE_M);
	localparam int MOCHA_L     = ridx(MOCHA, SIZE_L);
	localparam int LATTE_S     = ridx(LATTE, SIZE_S);
	localparam int LATTE_M     = ridx(LATTE, SIZE_M);
	localparam int LATTE_L     = ridx(LATTE, SIZE_L);
	localparam int ESPR_S      = ridx(ESPRESSO, SIZE_S);
	localparam int ESPR_M      = ridx(ESPRESSO, SIZE_M);
	localparam int ESPR_L      = ridx(ESPRESSO, SIZE_L);
	localparam int AMER_S      = ridx(AMERICANO, SIZE_S);
	localparam int AMER_M      = ridx(AMERICANO, SIZE_M);
	localparam int AMER_L      = ridx(AMERICANO, SIZE_L);
	localparam int DRIP_S      = ridx(DRIP, SIZE_S);
	localparam int DRIP_M      = ridx(DRIP, SIZE_M);
	localparam int DRIP_L      = ridx(DRIP, SIZE_L);

	// Initialize the recipe table with reasonable defaults (all time fields are 4 bits: 0..15 seconds)
	// Interpretation examples:
	//  - pour_time: seconds to pour water over grounds
	//  - hot_water_time: seconds to pour plain hot water
	//  - grinder_time: seconds to run grinder
	//  - cocoa_time: seconds to run cocoa motor
	initial begin
		// Mocha (chocolate + espresso + milk)
		recipes[MOCHA_S] = set_recipe(1'b0, 1'b1, 4'd4, 4'd2, 4'd3, 4'd2, 1'b0);
		recipes[MOCHA_M] = set_recipe(1'b0, 1'b1, 4'd6, 4'd3, 4'd4, 4'd3, 1'b0);
		recipes[MOCHA_L] = set_recipe(1'b0, 1'b1, 4'd8, 4'd4, 4'd5, 4'd4, 1'b0);

		// Latte (espresso + steamed milk; cocoa_time typically 0)
		recipes[LATTE_S] = set_recipe(1'b0, 1'b1, 4'd4, 4'd6, 4'd3, 4'd0, 1'b1);
		recipes[LATTE_M] = set_recipe(1'b0, 1'b1, 4'd6, 4'd8, 4'd4, 4'd0, 1'b1);
		recipes[LATTE_L] = set_recipe(1'b0, 1'b1, 4'd8, 4'd10, 4'd5, 4'd0, 1'b1);

		// Espresso (short pour, fine grind)
		recipes[ESPR_S]  = set_recipe(1'b0, 1'b1, 4'd2, 4'd0, 4'd5, 4'd0, 1'b0);
		recipes[ESPR_M]  = set_recipe(1'b0, 1'b1, 4'd3, 4'd0, 4'd6, 4'd0, 1'b0);
		recipes[ESPR_L]  = set_recipe(1'b0, 1'b1, 4'd4, 4'd0, 4'd7, 4'd0, 1'b0);

		// Americano (espresso + hot water)
		recipes[AMER_S]  = set_recipe(1'b0, 1'b1, 4'd2, 4'd6, 4'd4, 4'd0, 1'b0);  // Watered down espresso
		recipes[AMER_M]  = set_recipe(1'b0, 1'b1, 4'd3, 4'd8, 4'd5, 4'd0, 1'b0);
		recipes[AMER_L]  = set_recipe(1'b0, 1'b1, 4'd4, 4'd10, 4'd6, 4'd0, 1'b0);

		// Drip (requires filter; longer pour/hot water)
		recipes[DRIP_S]  = set_recipe(1'b1, 1'b0, 4'd6, 4'd12, 4'd4, 4'd0, 1'b0);   // Use low pressure
		recipes[DRIP_M]  = set_recipe(1'b1, 1'b0, 4'd8, 4'd14, 4'd5, 4'd0, 1'b0);   // longer time
		recipes[DRIP_L]  = set_recipe(1'b1, 1'b0, 4'd10, 4'd15, 4'd6, 4'd0, 1'b0);
	end

	// (helper function defined earlier)
endmodule

