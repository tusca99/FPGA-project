############## NET - IOSTANDARD ######################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
#############SPI Configurate Setting##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
############## clock define###########################
#create_clock -period 5.000 [get_ports sys_clk_p]
set_property PACKAGE_PIN R4 [get_ports sys_clk_p]
set_property IOSTANDARD DIFF_SSTL15 [get_ports sys_clk_p]
#sys_clk_n is pin T4 but that is done automatically
#################reset setting########################
#set_property IOSTANDARD LVCMOS15 [get_ports rstExt]
#set_property PACKAGE_PIN T6 [get_ports rstExt]

#############LED Setting###########################
set_property PACKAGE_PIN E17 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN F16 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN W5 [get_ports ledFPGA]
set_property IOSTANDARD LVCMOS15 [get_ports ledFPGA]

#set_property PACKAGE_PIN E16 [get_ports {key2}]
#set_property IOSTANDARD LVCMOS33 [get_ports {key2}]

set_property PACKAGE_PIN D16 [get_ports key1]
set_property IOSTANDARD LVCMOS33 [get_ports key1]

#####################Synchronisation Lines via 10pol cable##############################
#E18 is the corresponding negative input/output
set_property PACKAGE_PIN F18 [get_ports AllBussyExt11]
set_property IOSTANDARD LVCMOS33 [get_ports AllBussyExt11]
set_property SLEW SLOW [get_ports AllBussyExt11]
set_property PULLTYPE PULLDOWN [get_ports AllBussyExt11]
set_property DRIVE 8 [get_ports AllBussyExt11]

#C19 is the corresponding negative input/output
set_property PACKAGE_PIN C18 [get_ports errorRxSyncExt11]
set_property IOSTANDARD LVCMOS33 [get_ports errorRxSyncExt11]
set_property SLEW SLOW [get_ports errorRxSyncExt11]
set_property PULLTYPE PULLDOWN [get_ports errorRxSyncExt11]
set_property DRIVE 8 [get_ports errorRxSyncExt11]

#B18 is the corresponding negative input/output
set_property PACKAGE_PIN B17 [get_ports AllBussyExt12]
set_property IOSTANDARD LVCMOS33 [get_ports AllBussyExt12]
set_property SLEW SLOW [get_ports AllBussyExt12]
set_property PULLTYPE PULLDOWN [get_ports AllBussyExt12]
set_property DRIVE 8 [get_ports AllBussyExt12]

#C17 is the corresponding negative input/output
set_property PACKAGE_PIN D17 [get_ports errorRxSyncExt12]
set_property IOSTANDARD LVCMOS33 [get_ports errorRxSyncExt12]
set_property SLEW SLOW [get_ports errorRxSyncExt12]
set_property PULLTYPE PULLDOWN [get_ports errorRxSyncExt12]
set_property DRIVE 8 [get_ports errorRxSyncExt12]

#G16 is the corresponding negative input/output
set_property PACKAGE_PIN G15 [get_ports AllBussyExt2]
set_property IOSTANDARD LVCMOS33 [get_ports AllBussyExt2]
set_property SLEW SLOW [get_ports AllBussyExt2]
set_property PULLTYPE PULLDOWN [get_ports AllBussyExt2]
set_property DRIVE 8 [get_ports AllBussyExt2]

#D19 is the corresponding negative input/output
set_property PACKAGE_PIN E19 [get_ports errorRxSyncExt2]
set_property IOSTANDARD LVCMOS33 [get_ports errorRxSyncExt2]
set_property SLEW SLOW [get_ports errorRxSyncExt2]
set_property PULLTYPE PULLDOWN [get_ports errorRxSyncExt2]
set_property DRIVE 8 [get_ports errorRxSyncExt2]

#######################DIPSwitch and Fan###############
set_property PACKAGE_PIN C22 [get_ports {DipSwitch[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[0]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[0]}]
set_property PACKAGE_PIN B20 [get_ports {DipSwitch[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[1]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[1]}]
set_property PACKAGE_PIN F19 [get_ports {DipSwitch[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[2]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[2]}]
set_property PACKAGE_PIN F15 [get_ports {DipSwitch[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[3]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[3]}]
set_property PACKAGE_PIN M17 [get_ports {DipSwitch[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[4]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[4]}]
set_property PACKAGE_PIN B21 [get_ports {DipSwitch[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[5]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[5]}]
set_property PACKAGE_PIN E21 [get_ports {DipSwitch[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[6]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[6]}]
set_property PACKAGE_PIN G17 [get_ports {DipSwitch[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {DipSwitch[7]}]
set_property PULLTYPE PULLUP [get_ports {DipSwitch[7]}]
set_property PACKAGE_PIN J19 [get_ports Fan]
set_property IOSTANDARD LVCMOS33 [get_ports Fan]
set_property PULLTYPE PULLUP [get_ports Fan]

###################MDIO##############################
set_property PACKAGE_PIN L16 [get_ports e1_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports e1_mdio]
set_property PACKAGE_PIN J17 [get_ports e1_mdc]
set_property IOSTANDARD LVCMOS33 [get_ports e1_mdc]
set_property PULLTYPE PULLUP [get_ports e1_mdc]
set_property SLEW SLOW [get_ports e1_mdio]
set_property PULLTYPE PULLUP [get_ports e1_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports e1_reset]
set_property PACKAGE_PIN G20 [get_ports e1_reset]

set_property PACKAGE_PIN V19 [get_ports e3_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports e3_mdio]
set_property PACKAGE_PIN V20 [get_ports e3_mdc]
set_property IOSTANDARD LVCMOS33 [get_ports e3_mdc]
set_property PULLTYPE PULLUP [get_ports e3_mdc]
set_property SLEW SLOW [get_ports e3_mdio]
set_property PULLTYPE PULLUP [get_ports e3_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports e3_reset]
set_property PACKAGE_PIN T20 [get_ports e3_reset]

set_property PACKAGE_PIN U20 [get_ports e4_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports e4_mdio]
set_property PACKAGE_PIN V18 [get_ports e4_mdc]
set_property IOSTANDARD LVCMOS33 [get_ports e4_mdc]
set_property PULLTYPE PULLUP [get_ports e4_mdc]
set_property SLEW SLOW [get_ports e4_mdio]
set_property PULLTYPE PULLUP [get_ports e4_mdio]
set_property IOSTANDARD LVCMOS33 [get_ports e4_reset]
set_property PACKAGE_PIN R16 [get_ports e4_reset]

############## ethernet PORT1 RX define############


create_clock -period 8.000 -name e1_clk [get_ports e1_rx_clk_from_pins]
set_input_jitter [get_clocks -of_objects [get_ports e1_rx_clk_from_pins]] 0.1
set_property IOSTANDARD LVCMOS33 [get_ports e1_rx_clk_from_pins]
set_property PACKAGE_PIN K18 [get_ports e1_rx_clk_from_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e1_rx_dv_from_pins]
set_property PACKAGE_PIN M22 [get_ports e1_rx_dv_from_pins]

#set_property IOSTANDARD LVCMOS33 [get_ports e1_rx_er]
#set_property PACKAGE_PIN N18 [get_ports e1_rx_er]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[0]}]
set_property PACKAGE_PIN N22 [get_ports {e1_rxd_from_pins[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[1]}]
set_property PACKAGE_PIN H18 [get_ports {e1_rxd_from_pins[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[2]}]
set_property PACKAGE_PIN H17 [get_ports {e1_rxd_from_pins[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[3]}]
set_property PACKAGE_PIN M21 [get_ports {e1_rxd_from_pins[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[4]}]
set_property PACKAGE_PIN L21 [get_ports {e1_rxd_from_pins[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[5]}]
set_property PACKAGE_PIN N20 [get_ports {e1_rxd_from_pins[5]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[6]}]
set_property PACKAGE_PIN M20 [get_ports {e1_rxd_from_pins[6]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_rxd_from_pins[7]}]
set_property PACKAGE_PIN N19 [get_ports {e1_rxd_from_pins[7]}]
############## ethernet PORT1 TX define##############

set_property IOSTANDARD LVCMOS33 [get_ports e1_tx_clk_to_pins]
set_property PACKAGE_PIN G21 [get_ports e1_tx_clk_to_pins]
#create_generated_clock -name e1_tx_clk -source [get_ports e1_clk] -divide_by 1 [get_ports e1_tx_clk]

set_property IOSTANDARD LVCMOS33 [get_ports e1_tx_en_to_pins]
set_property PACKAGE_PIN G22 [get_ports e1_tx_en_to_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e1_tx_er]
set_property PACKAGE_PIN K17 [get_ports e1_tx_er]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[0]}]
set_property PACKAGE_PIN D22 [get_ports {e1_txd_to_pins[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[1]}]
set_property PACKAGE_PIN H20 [get_ports {e1_txd_to_pins[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[2]}]
set_property PACKAGE_PIN H22 [get_ports {e1_txd_to_pins[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[3]}]
set_property PACKAGE_PIN J22 [get_ports {e1_txd_to_pins[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[4]}]
set_property PACKAGE_PIN K22 [get_ports {e1_txd_to_pins[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[5]}]
set_property PACKAGE_PIN L19 [get_ports {e1_txd_to_pins[5]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[6]}]
set_property PACKAGE_PIN K19 [get_ports {e1_txd_to_pins[6]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e1_txd_to_pins[7]}]
set_property PACKAGE_PIN L20 [get_ports {e1_txd_to_pins[7]}]



############## ethernet PORT3 RX define##################
create_clock -period 8.000 -name e3_clk [get_ports e3_rx_clk_from_pins]
set_input_jitter [get_clocks -of_objects [get_ports e3_rx_clk_from_pins]] 0.1
set_property IOSTANDARD LVCMOS33 [get_ports e3_rx_clk_from_pins]
set_property PACKAGE_PIN V13 [get_ports e3_rx_clk_from_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e3_rx_dv_from_pins]
set_property PACKAGE_PIN AA20 [get_ports e3_rx_dv_from_pins]

#set_property IOSTANDARD LVCMOS33 [get_ports e3_rx_er]
#set_property PACKAGE_PIN U21 [get_ports e3_rx_er]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[0]}]
set_property PACKAGE_PIN AB20 [get_ports {e3_rxd_from_pins[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[1]}]
set_property PACKAGE_PIN AA19 [get_ports {e3_rxd_from_pins[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[2]}]
set_property PACKAGE_PIN AA18 [get_ports {e3_rxd_from_pins[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[3]}]
set_property PACKAGE_PIN AB18 [get_ports {e3_rxd_from_pins[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[4]}]
set_property PACKAGE_PIN Y17 [get_ports {e3_rxd_from_pins[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[5]}]
set_property PACKAGE_PIN W22 [get_ports {e3_rxd_from_pins[5]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[6]}]
set_property PACKAGE_PIN W21 [get_ports {e3_rxd_from_pins[6]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_rxd_from_pins[7]}]
set_property PACKAGE_PIN T21 [get_ports {e3_rxd_from_pins[7]}]
############## ethernet PORT3 TX define##################
set_property IOSTANDARD LVCMOS33 [get_ports e3_tx_clk_to_pins]
set_property PACKAGE_PIN AA21 [get_ports e3_tx_clk_to_pins]
#create_generated_clock -name e3_tx_clk -source [get_ports e3_rx_clk_from_pins] -divide_by 1 [get_ports e3_tx_clk_to_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e3_tx_en_to_pins]
set_property PACKAGE_PIN V14 [get_ports e3_tx_en_to_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e3_tx_er]
set_property PACKAGE_PIN AA9 [get_ports e3_tx_er]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[0]}]
set_property PACKAGE_PIN W11 [get_ports {e3_txd_to_pins[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[1]}]
set_property PACKAGE_PIN W12 [get_ports {e3_txd_to_pins[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[2]}]
set_property PACKAGE_PIN Y11 [get_ports {e3_txd_to_pins[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[3]}]
set_property PACKAGE_PIN Y12 [get_ports {e3_txd_to_pins[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[4]}]
set_property PACKAGE_PIN W10 [get_ports {e3_txd_to_pins[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[5]}]
set_property PACKAGE_PIN AA11 [get_ports {e3_txd_to_pins[5]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[6]}]
set_property PACKAGE_PIN AA10 [get_ports {e3_txd_to_pins[6]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e3_txd_to_pins[7]}]
set_property PACKAGE_PIN AB10 [get_ports {e3_txd_to_pins[7]}]


############## ethernet PORT4 RX define##################
create_clock -period 8.000 -name e4_clk [get_ports e4_rx_clk_from_pins]
set_input_jitter [get_clocks -of_objects [get_ports e4_rx_clk_from_pins]] 0.1
set_property IOSTANDARD LVCMOS33 [get_ports e4_rx_clk_from_pins]
set_property PACKAGE_PIN Y18 [get_ports e4_rx_clk_from_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e4_rx_dv_from_pins]
set_property PACKAGE_PIN W20 [get_ports e4_rx_dv_from_pins]

#set_property IOSTANDARD LVCMOS33 [get_ports e4_rx_er]
#set_property PACKAGE_PIN N13 [get_ports e4_rx_er]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[0]}]
set_property PACKAGE_PIN W19 [get_ports {e4_rxd_from_pins[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[1]}]
set_property PACKAGE_PIN Y19 [get_ports {e4_rxd_from_pins[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[2]}]
set_property PACKAGE_PIN V22 [get_ports {e4_rxd_from_pins[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[3]}]
set_property PACKAGE_PIN U22 [get_ports {e4_rxd_from_pins[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[4]}]
set_property PACKAGE_PIN T18 [get_ports {e4_rxd_from_pins[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[5]}]
set_property PACKAGE_PIN R18 [get_ports {e4_rxd_from_pins[5]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[6]}]
set_property PACKAGE_PIN R14 [get_ports {e4_rxd_from_pins[6]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_rxd_from_pins[7]}]
set_property PACKAGE_PIN P14 [get_ports {e4_rxd_from_pins[7]}]
############## ethernet PORT4 TX define##################
set_property IOSTANDARD LVCMOS33 [get_ports e4_tx_clk_to_pins]
set_property PACKAGE_PIN P20 [get_ports e4_tx_clk_to_pins]
#create_generated_clock -name e4_tx_clk -source [get_ports e4_rx_clk_from_pins] -divide_by 1 [get_ports e4_tx_clk_to_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e4_tx_en_to_pins]
set_property PACKAGE_PIN P16 [get_ports e4_tx_en_to_pins]

set_property IOSTANDARD LVCMOS33 [get_ports e4_tx_er]
set_property PACKAGE_PIN R19 [get_ports e4_tx_er]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[0]}]
set_property PACKAGE_PIN R17 [get_ports {e4_txd_to_pins[0]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[1]}]
set_property PACKAGE_PIN P15 [get_ports {e4_txd_to_pins[1]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[2]}]
set_property PACKAGE_PIN N17 [get_ports {e4_txd_to_pins[2]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[3]}]
set_property PACKAGE_PIN P17 [get_ports {e4_txd_to_pins[3]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[4]}]
set_property PACKAGE_PIN T16 [get_ports {e4_txd_to_pins[4]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[5]}]
set_property PACKAGE_PIN U17 [get_ports {e4_txd_to_pins[5]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[6]}]
set_property PACKAGE_PIN U18 [get_ports {e4_txd_to_pins[6]}]

set_property IOSTANDARD LVCMOS33 [get_ports {e4_txd_to_pins[7]}]
set_property PACKAGE_PIN P19 [get_ports {e4_txd_to_pins[7]}]


#***********************************************CLK and Delay constraints********************************#
#clock domain transfers
#CaclClk to e1_clk
#IOclk to e1_clk
#e1_clk to IOclk
#IOclk to e3_clk
#IOclk to e4_clk

#e3_clk to IOclk
set_false_path -from [get_pins {BroadcastAtom/ETHlink_top3/ETH_rx/data_recv_d0_reg*/C}] -to [get_pins {BroadcastAtom/ETHlink_top3/ETH_rx/data_recv_reg*/D}] 
set_max_delay  -from [get_pins {BroadcastAtom/ETHlink_top3/ETH_rx/data_recv_d0_reg*/C}] -to [get_pins {BroadcastAtom/ETHlink_top3/ETH_rx/data_recv_reg*/D}] 15.000

#e4_clk to IOclk
set_false_path -from [get_pins {BroadcastAtom/ETHlink_top4/ETH_rx/data_recv_d0_reg*/C}] -to [get_pins {BroadcastAtom/ETHlink_top4/ETH_rx/data_recv_reg*/D}] 
set_max_delay  -from [get_pins {BroadcastAtom/ETHlink_top4/ETH_rx/data_recv_d0_reg*/C}] -to [get_pins {BroadcastAtom/ETHlink_top4/ETH_rx/data_recv_reg*/D}] 15.000

#IOclk to CalcClk
#set_false_path -from [get_pins MDmachine/iHalf_reg/C] -to [get_pins MDmachine/iHalf_d0_reg/D]
#set_false_path -from [get_pins MDmachine/CalcBussy_reg/C] -to [get_pins MDmachine/CalcBussy_d0_reg/D]
#set _xlnx_shared_i0 [get_pins MDmachine/nAtom_reg*/C]
#set_false_path -from $_xlnx_shared_i0 -to [get_pins MDmachine/nAtom_iH0_d0_reg*/D]
#set_false_path -from $_xlnx_shared_i0 -to [get_pins MDmachine/nAtom_iH1_d0_reg*/D]
#set_false_path -from $_xlnx_shared_i0 -to [get_pins mac1/nAtom_d1_reg*/D]
#set_false_path -from [get_pins mac1/ReadCommand/nSend_reg*/C] -to [get_pins mac1/nSend_d1_reg*/D]
#set_false_path -from [get_pins mac1/statusLine_d0_reg*/C] -to [get_pins mac1/statusLine_d1_reg*/D]

set_false_path -from [get_pins {MDmachine/SendMacBox_d0_reg*/C}] -to [get_pins {MDmachine/SendMacBox_CalcClk_reg*/D}] 
set_max_delay  -from [get_pins {MDmachine/SendMacBox_d0_reg*/C}] -to [get_pins {MDmachine/SendMacBox_CalcClk_reg*/D}] 30.000

#CalcClk to IOclk

#IOClk to gtp_clk

#gtp_clk to IOClk
set_false_path -from [get_pins {BroadcastAtom/GTP_top/gtp0_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp0_rx/data_recv_reg*/D}] 
set_max_delay  -from [get_pins {BroadcastAtom/GTP_top/gtp0_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp0_rx/data_recv_reg*/D}] 15.000
set_false_path -from [get_pins {BroadcastAtom/GTP_top/gtp1_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp1_rx/data_recv_reg*/D}] 
set_max_delay  -from [get_pins {BroadcastAtom/GTP_top/gtp1_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp1_rx/data_recv_reg*/D}] 15.000
set_false_path -from [get_pins {BroadcastAtom/GTP_top/gtp2_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp2_rx/data_recv_reg*/D}] 
set_max_delay  -from [get_pins {BroadcastAtom/GTP_top/gtp2_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp2_rx/data_recv_reg*/D}] 15.000
set_false_path -from [get_pins {BroadcastAtom/GTP_top/gtp3_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp3_rx/data_recv_reg*/D}] 
set_max_delay  -from [get_pins {BroadcastAtom/GTP_top/gtp3_rx/data_recv_d2_reg*/C}] -to [get_pins {BroadcastAtom/GTP_top/gtp3_rx/data_recv_reg*/D}] 15.000



#****************************************INPUT and OUTPUT delays********************************************
#max 5.5; is tGCC(8ns)-tGSUT in data sheet
#min 0.5; is  tGHTT in data sheet
#may try 5.3 and 0.7 for more relaxed timing
#set_input_delay -clock e1_clk -max 5.500 e1_rxd
#set_input_delay -clock e1_clk -max 5.500 e1_rx_dv
#set_input_delay -clock e1_clk -min 0.500 e1_rx_dv
#set_input_delay -clock e1_clk -min 0.500 e1_rxd

#set_input_delay -clock e3_clk -max 5.500 e3_rxd
#set_input_delay -clock e3_clk -max 5.500 e3_rx_dv
#set_input_delay -clock e3_clk -min 0.500 e3_rx_dv
#set_input_delay -clock e3_clk -min 0.500 e3_rxd
#set_input_delay -clock e3_clk -max 5.500 e3_rx_er
#set_input_delay -clock e3_clk -min 0.500 e3_rx_er

#set_input_delay -clock e4_clk -max 5.500 e4_rxd
#set_input_delay -clock e4_clk -max 5.500 e4_rx_dv
#set_input_delay -clock e4_clk -min 0.500 e4_rx_dv
#set_input_delay -clock e4_clk -min 0.500 e4_rxd
#set_input_delay -clock e4_clk -max 5.500 e4_rx_er
#set_input_delay -clock e4_clk -min 0.500 e4_rx_er

#2.0 ns; is tGSUR in data sheet
#0 ns; is tGHTR in data sheet
#playing with numbers revealed that 4.0 ns and 0 ns might be a bit better.
#set_output_delay -clock e1_tx_clk -max 4.000 e1_txd
#set_output_delay -clock e1_tx_clk -max 4.000 e1_tx_en
#set_output_delay -clock e1_tx_clk -min -0.000 e1_tx_en
#set_output_delay -clock e1_tx_clk -min -0.000 e1_txd

#set_output_delay -clo#ck e3_tx_clk -max 4.000 e3_txd
#set_output_delay -clock e3_tx_clk -max 4.000 e3_tx_en
#set_output_delay -clock e3_tx_clk -min -0.000 e3_tx_en
#set_output_delay -clock e3_tx_clk -min -0.000 e3_txd

#set_output_delay -clock e4_tx_clk -max 4.000 e4_txd
#set_output_delay -clock e4_tx_clk -max 4.000 e4_tx_en
#set_output_delay -clock e4_tx_clk -min -0.000 e4_tx_en
#set_output_delay -clock e4_tx_clk -min -0.000 e4_txd

#ETH-IO ports. they are time-critical, but programmed with IOB registers and proper delay lines, as such timing is guaranteed. 
#set_false_path them to remove warning
set_false_path -to [get_ports e1_tx_clk_to_pins]
set_false_path -to [get_ports e1_tx_en_to_pins]
set_false_path -to [get_ports e1_txd_to_pins]
set_false_path -to [get_ports e3_tx_clk_to_pins]
set_false_path -to [get_ports e3_tx_en_to_pins]
set_false_path -to [get_ports e3_txd_to_pins]
set_false_path -to [get_ports e4_tx_clk_to_pins]
set_false_path -to [get_ports e4_tx_en_to_pins]
set_false_path -to [get_ports e4_txd_to_pins]

set_false_path -from [get_ports e1_rxd_from_pins]
set_false_path -from [get_ports e1_rx_dv_from_pins]
set_false_path -from [get_ports e3_rxd_from_pins]
set_false_path -from [get_ports e3_rx_dv_from_pins]
set_false_path -from [get_ports e4_rxd_from_pins]
set_false_path -from [get_ports e4_rx_dv_from_pins]


#IO ports that are not time-critical
set_false_path -to [get_ports e1_mdc]
set_false_path -to [get_ports e1_mdio]
set_false_path -to [get_ports e3_mdc]
set_false_path -to [get_ports e3_mdio]
set_false_path -to [get_ports e4_mdc]
set_false_path -to [get_ports e4_mdio]
set_false_path -to [get_ports ledFPGA]
set_false_path -to [get_ports led]
set_false_path -to [get_ports e1_reset]
set_false_path -to [get_ports e3_reset]
set_false_path -to [get_ports e4_reset]
set_false_path -to [get_ports errorRxSyncExt11]
set_false_path -to [get_ports AllBussyExt11]
set_false_path -to [get_ports AllBussyExt2]

set_false_path -from [get_ports e1_mdio]
set_false_path -from [get_ports e3_mdio]
set_false_path -from [get_ports e4_mdio]
set_false_path -from [get_ports DipSwitch]
set_false_path -from [get_ports AllBussyExt11]
set_false_path -from [get_ports AllBussyExt12]
set_false_path -from [get_ports Fan]
set_false_path -from [get_ports errorRxSyncExt11]
set_false_path -from [get_ports errorRxSyncExt12]
set_false_path -from [get_ports key1]
#******************************GTP interfaces************************************

set_property PACKAGE_PIN F6 [get_ports Q0_CLK0_GTREFCLK_PAD_P_IN]
set_property PACKAGE_PIN E6 [get_ports Q0_CLK0_GTREFCLK_PAD_N_IN]
create_clock -period 8.000 [get_ports Q0_CLK0_GTREFCLK_PAD_P_IN]


set_property IOSTANDARD LVCMOS33 [get_ports {gtp_tx_disable[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gtp_tx_disable[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gtp_tx_disable[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {gtp_tx_disable[0]}]
set_property PACKAGE_PIN A15 [get_ports {gtp_tx_disable[0]}]
set_property PACKAGE_PIN A16 [get_ports {gtp_tx_disable[1]}]
set_property PACKAGE_PIN A13 [get_ports {gtp_tx_disable[2]}]
set_property PACKAGE_PIN A14 [get_ports {gtp_tx_disable[3]}]

set_property LOC GTPE2_CHANNEL_X0Y4 [get_cells BroadcastAtom/GTP_top/gtp_exdes/gtp_support_i/gtp_init_i/inst/gtp_i/gt0_gtp_i/gtpe2_i]
set_property LOC GTPE2_CHANNEL_X0Y5 [get_cells BroadcastAtom/GTP_top/gtp_exdes/gtp_support_i/gtp_init_i/inst/gtp_i/gt1_gtp_i/gtpe2_i]
set_property LOC GTPE2_CHANNEL_X0Y6 [get_cells BroadcastAtom/GTP_top/gtp_exdes/gtp_support_i/gtp_init_i/inst/gtp_i/gt2_gtp_i/gtpe2_i]
set_property LOC GTPE2_CHANNEL_X0Y7 [get_cells BroadcastAtom/GTP_top/gtp_exdes/gtp_support_i/gtp_init_i/inst/gtp_i/gt3_gtp_i/gtpe2_i]

set_false_path -to [get_pins {BroadcastAtom/GTP_top/gtp_exdes/gt0_txfsmresetdone_r2_reg/CLR BroadcastAtom/GTP_top/gtp_exdes/gt0_txfsmresetdone_r_reg/CLR BroadcastAtom/GTP_top/gtp_exdes/gt1_txfsmresetdone_r2_reg/CLR BroadcastAtom/GTP_top/gtp_exdes/gt1_txfsmresetdone_r_reg/CLR BroadcastAtom/GTP_top/gtp_exdes/gt2_txfsmresetdone_r2_reg/CLR BroadcastAtom/GTP_top/gtp_exdes/gt2_txfsmresetdone_r_reg/CLR BroadcastAtom/GTP_top/gtp_exdes/gt3_txfsmresetdone_r2_reg/CLR BroadcastAtom/GTP_top/gtp_exdes/gt3_txfsmresetdone_r_reg/CLR}]
set_false_path -to [get_pins {BroadcastAtom/GTP_top/gtp_exdes/gt0_txfsmresetdone_r2_reg/D BroadcastAtom/GTP_top/gtp_exdes/gt0_txfsmresetdone_r_reg/D BroadcastAtom/GTP_top/gtp_exdes/gt1_txfsmresetdone_r2_reg/D BroadcastAtom/GTP_top/gtp_exdes/gt1_txfsmresetdone_r_reg/D BroadcastAtom/GTP_top/gtp_exdes/gt2_txfsmresetdone_r2_reg/D BroadcastAtom/GTP_top/gtp_exdes/gt2_txfsmresetdone_r_reg/D BroadcastAtom/GTP_top/gtp_exdes/gt3_txfsmresetdone_r2_reg/D BroadcastAtom/GTP_top/gtp_exdes/gt3_txfsmresetdone_r_reg/D}]




#******************************ILA's****************************************************

