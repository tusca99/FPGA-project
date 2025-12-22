close_hw_manager
open_hw_manager
connect_hw_server -allow_non_jtag
#
#first target
for {set i 0} {$i < 27} {incr i} {
  open_hw_target [lindex [get_hw_targets] $i]
  current_hw_device [get_hw_devices]
  set_property PROGRAM.FILE {C:/Users/phamm/PCI/projekte/2024/MD_FPGA/FPGAProgram/MD1/MD1.runs/impl_1/MD.bit} [current_hw_device]
  program_hw_devices [current_hw_device]
  close_hw_target
}
#
close_hw_manager


