# ===========================================================================
#  Arcade-ITech8.sdc -- timing constraints for the core
#
#  sys/sys_top.sdc constrains the framework. The PLL outputs (clk_sys 48 MHz,
#  clk_vid 96 MHz) come from derive_pll_clocks there; the 48 -> 96 MHz
#  video transfer is between related clocks and is analysed normally.
# ===========================================================================

# fx68k: the microcode ROM address is not needed until the next CPU clock
# (see rtl/fx68k/README.md, fx68k.txt upstream). The CPU runs at a quarter of
# clk_sys, so two clocks are always available.
set_multicycle_path -start -setup -from [get_keepers {*|fx68k:cpu|Ir[*]}] -to [get_keepers {*|fx68k:cpu|microAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {*|fx68k:cpu|Ir[*]}] -to [get_keepers {*|fx68k:cpu|microAddr[*]}] 1
set_multicycle_path -start -setup -from [get_keepers {*|fx68k:cpu|Ir[*]}] -to [get_keepers {*|fx68k:cpu|nanoAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {*|fx68k:cpu|Ir[*]}] -to [get_keepers {*|fx68k:cpu|nanoAddr[*]}] 1
