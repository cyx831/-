# Generated at 2026-10-28 00:07

set_arch -family Logos -device PGL50H -package FBG484 -speedgrade -6
add_design "D:/FPGA_Competition/10_HDMI_DDR3_OV5640_test/10_HDMI_DDR3_OV5640_test/ipcore/bbox_rom/rtl/ipml_rom_v1_5_bbox_rom_ip.v"
add_design "D:/FPGA_Competition/10_HDMI_DDR3_OV5640_test/10_HDMI_DDR3_OV5640_test/ipcore/bbox_rom/rtl/ipml_spram_v1_5_bbox_rom_ip.v"
add_design "D:/FPGA_Competition/10_HDMI_DDR3_OV5640_test/10_HDMI_DDR3_OV5640_test/ipcore/bbox_rom/bbox_rom_ip.v"
compile -top_module bbox_rom_ip
synthesize -ads
