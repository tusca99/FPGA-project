write_cfgmem  -format mcs -size 16 -interface SPIx4 -loadbit {up 0x00000000 "C:/Users/phamm/PCI/projekte/2024/MD_FPGA/FPGAProgram/MD1/MD1.runs/impl_1/MD.bit" } -force -file "C:/Users/phamm/PCI/projekte/2024/MD_FPGA/FPGAProgram/MD1/config.mcs"

close_hw_manager
open_hw_manager
connect_hw_server -allow_non_jtag

for {set i 0} {$i < 27} {incr i} {
  open_hw_target [lindex [get_hw_targets] $i]
  after 1000
  create_hw_cfgmem -hw_device [get_hw_devices] -mem_dev  [lindex [get_cfgmem_parts {mt25ql128-spi-x1_x2_x4}] 0]
  current_hw_device [get_hw_devices]
  set_property PROGRAM.ADDRESS_RANGE  {use_file} [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  set_property PROGRAM.FILES [list "C:/Users/phamm/PCI/projekte/2024/MD_FPGA/FPGAProgram/MD1/config.mcs" ] [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  set_property PROGRAM.UNUSED_PIN_TERMINATION {pull-none} [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  set_property PROGRAM.BLANK_CHECK  0 [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  set_property PROGRAM.ERASE  1 [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  set_property PROGRAM.CFG_PROGRAM  1 [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  set_property PROGRAM.VERIFY  1 [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  set_property PROGRAM.CHECKSUM  0 [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  startgroup 
  create_hw_bitstream -hw_device [current_hw_device] [get_property PROGRAM.HW_CFGMEM_BITFILE [current_hw_device]]; program_hw_devices [current_hw_device]; refresh_hw_device [current_hw_device];
  program_hw_cfgmem -hw_cfgmem [ get_property PROGRAM.HW_CFGMEM [current_hw_device]]
  close_hw_target
}

close_hw_manager



