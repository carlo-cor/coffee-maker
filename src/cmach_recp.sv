`include "cmach_recipes.svh"

module cmach_recp (
    output logic [$bits(coffee_recipe_t)-1:0] recipes [0:14]
);

    localparam int NUM_SIZES   = 3;
    localparam int NUM_RECIPES = 15;

    localparam int MOCHA     = 0;
    localparam int LATTE     = 1;
    localparam int ESPRESSO  = 2;
    localparam int AMERICANO = 3;
    localparam int DRIP      = 4;

    localparam int SIZE_S = 0;
    localparam int SIZE_M = 1;
    localparam int SIZE_L = 2;

    function automatic int ridx(input int d, input int size_idx);
        ridx = d * NUM_SIZES + size_idx;
    endfunction

    function automatic coffee_recipe_t set_recipe(
        input logic       load_filter_in,
        input logic       high_press_in,
        input logic [3:0] pour_time_in,
        input logic [3:0] hot_water_time_in,
        input logic [3:0] grinder_time_in,
        input logic [3:0] cocoa_time_in,
        input logic       add_creamer_in
    );
        set_recipe = '{load_filter_in, high_press_in, pour_time_in, hot_water_time_in,
                       grinder_time_in, cocoa_time_in, add_creamer_in};
    endfunction

    localparam int MOCHA_S = ridx(MOCHA, SIZE_S);
    localparam int MOCHA_M = ridx(MOCHA, SIZE_M);
    localparam int MOCHA_L = ridx(MOCHA, SIZE_L);

    localparam int LATTE_S = ridx(LATTE, SIZE_S);
    localparam int LATTE_M = ridx(LATTE, SIZE_M);
    localparam int LATTE_L = ridx(LATTE, SIZE_L);

    localparam int ESPR_S  = ridx(ESPRESSO, SIZE_S);
    localparam int ESPR_M  = ridx(ESPRESSO, SIZE_M);
    localparam int ESPR_L  = ridx(ESPRESSO, SIZE_L);

    localparam int AMER_S  = ridx(AMERICANO, SIZE_S);
    localparam int AMER_M  = ridx(AMERICANO, SIZE_M);
    localparam int AMER_L  = ridx(AMERICANO, SIZE_L);

    localparam int DRIP_S  = ridx(DRIP, SIZE_S);
    localparam int DRIP_M  = ridx(DRIP, SIZE_M);
    localparam int DRIP_L  = ridx(DRIP, SIZE_L);

    integer i;
    always_comb begin
        for (i = 0; i < NUM_RECIPES; i = i + 1)
            recipes[i] = '0;

        // Mocha
        recipes[MOCHA_S] = set_recipe(1'b0, 1'b1, 4'd4,  4'd2,  4'd3, 4'd2, 1'b0);
        recipes[MOCHA_M] = set_recipe(1'b0, 1'b1, 4'd6,  4'd3,  4'd4, 4'd3, 1'b0);
        recipes[MOCHA_L] = set_recipe(1'b0, 1'b1, 4'd8,  4'd4,  4'd5, 4'd4, 1'b0);

        // Latte
        recipes[LATTE_S] = set_recipe(1'b0, 1'b1, 4'd4,  4'd6,  4'd3, 4'd0, 1'b1);
        recipes[LATTE_M] = set_recipe(1'b0, 1'b1, 4'd6,  4'd8,  4'd4, 4'd0, 1'b1);
        recipes[LATTE_L] = set_recipe(1'b0, 1'b1, 4'd8,  4'd10, 4'd5, 4'd0, 1'b1);

        // Espresso
        recipes[ESPR_S]  = set_recipe(1'b0, 1'b1, 4'd2,  4'd0,  4'd5, 4'd0, 1'b0);
        recipes[ESPR_M]  = set_recipe(1'b0, 1'b1, 4'd3,  4'd0,  4'd6, 4'd0, 1'b0);
        recipes[ESPR_L]  = set_recipe(1'b0, 1'b1, 4'd4,  4'd0,  4'd7, 4'd0, 1'b0);

        // Americano
        recipes[AMER_S]  = set_recipe(1'b0, 1'b1, 4'd2,  4'd6,  4'd4, 4'd0, 1'b0);
        recipes[AMER_M]  = set_recipe(1'b0, 1'b1, 4'd3,  4'd8,  4'd5, 4'd0, 1'b0);
        recipes[AMER_L]  = set_recipe(1'b0, 1'b1, 4'd4,  4'd10, 4'd6, 4'd0, 1'b0);

        // Drip
        recipes[DRIP_S]  = set_recipe(1'b1, 1'b0, 4'd6,  4'd12, 4'd4, 4'd0, 1'b0);
        recipes[DRIP_M]  = set_recipe(1'b1, 1'b0, 4'd8,  4'd14, 4'd5, 4'd0, 1'b0);
        recipes[DRIP_L]  = set_recipe(1'b1, 1'b0, 4'd10, 4'd15, 4'd6, 4'd0, 1'b0);
    end

endmodule
