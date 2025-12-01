`ifndef __COFFEE_RECIPES_SVH__
`define __COFFEE_RECIPES_SVH__

// Packed struct to describe a coffee "recipe" for FPGA control
// Fields (packed order: first declared = MSB of the packed vector):
//  - load_filter        : 1 bit   (1 = load fresh filter/paper)
//  - high_press         : 1 bit   (1 = use high-pressure brew; 0 = low pressure)
//  - pour_time          : 4 bits  (seconds to pour water over grounds)
//  - hot_water_time     : 4 bits  (seconds to pour plain hot water)
//  - grinder_time       : 4 bits  (seconds to run coffee grinder)
//  - cocoa_time         : 4 bits  (seconds to run cocoa powder motor)
//  - add_creamer        : 1 bit   (1 = add non-dairy creamer)
// Adjust bit-widths as needed for your application; these provide generous ranges.

typedef struct packed {
    logic         load_filter;        // 1 bit
    logic         high_press;         // 1 bit
    logic [3:0]   pour_time;          // seconds (0..15)
    logic [3:0]   hot_water_time;     // seconds (0..15)
    logic [3:0]   grinder_time;       // seconds (0..15)
    logic [3:0]   cocoa_time;         // seconds (0..15)
    logic         add_creamer;        // 1 bit
} coffee_recipe_t;

`define COFFEE_RECIPE_W $bits(coffee_recipe_t)

`endif // __COFFEE_RECIPES_SVH__
