# Generated at 2026-10-28 00:45

set_arch -family Logos -device PGL50H -package FBG484 -speedgrade -6
add_design "D:/FPGA_Competition/10_HDMI_DDR3_OV5640_test/10_HDMI_DDR3_OV5640_test/ipcore/lut_rom/rtl/ipml_rom_v1_5_lut_rom_ip.v"
add_design "D:/FPGA_Competition/10_HDMI_DDR3_OV5640_test/10_HDMI_DDR3_OV5640_test/ipcore/lut_rom/rtl/ipml_spram_v1_5_lut_rom_ip.v"
add_design "D:/FPGA_Competition/10_HDMI_DDR3_OV5640_test/10_HDMI_DDR3_OV5640_test/ipcore/lut_rom/lut_rom_ip.v"
compile -top_module lut_rom_ip
synthesize -ads
