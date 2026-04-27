## Clock signal
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports Clk]
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} -add [get_ports Clk]

## Reset
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports Rst]

## Switches
#set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { Sel[0] }]; #IO_L12N_T1_MRCC_16 Sch=sw[0]
#set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { Sel[1] }]; #IO_L13P_T2_MRCC_16 Sch=sw[1]
#set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { Sel[2] }]; #IO_L13N_T2_MRCC_16 Sch=sw[2]
#set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { Sel[3] }]; #IO_L14P_T2_SRCC_16 Sch=sw[3]

## RGB LEDs
# Blue / Green / Red on led0, mapped to led_rgb_o(0..2)
set_property -dict {PACKAGE_PIN E1 IOSTANDARD LVCMOS33} [get_ports {led_rgb_o[0]}]
set_property -dict {PACKAGE_PIN F6 IOSTANDARD LVCMOS33} [get_ports {led_rgb_o[1]}]
set_property -dict {PACKAGE_PIN G6 IOSTANDARD LVCMOS33} [get_ports {led_rgb_o[2]}]
#set_property -dict { PACKAGE_PIN G4    IOSTANDARD LVCMOS33 } [get_ports { output_2[0] }]; #IO_L20P_T3_35 Sch=led1_b
#set_property -dict { PACKAGE_PIN J4    IOSTANDARD LVCMOS33 } [get_ports { output_2[1] }]; #IO_L21P_T3_DQS_35 Sch=led1_g
#set_property -dict { PACKAGE_PIN G3    IOSTANDARD LVCMOS33 } [get_ports { output_2[2] }]; #IO_L20N_T3_35 Sch=led1_r
#set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports { output_3[0] }]; #IO_L21N_T3_DQS_35 Sch=led2_b
#set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { output_3[1] }]; #IO_L22N_T3_35 Sch=led2_g
#set_property -dict { PACKAGE_PIN J3    IOSTANDARD LVCMOS33 } [get_ports { output_3[2] }]; #IO_L22P_T3_35 Sch=led2_r
#set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { output_4[0] }]; #IO_L23P_T3_35 Sch=led3_b
#set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { output_4[1] }]; #IO_L24P_T3_35 Sch=led3_g
#set_property -dict { PACKAGE_PIN K1    IOSTANDARD LVCMOS33 } [get_ports { output_4[2] }]; #IO_L23N_T3_35 Sch=led3_r

## Buttons
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports btn_init_i]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports btn_run_i]
#set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports { btn[2] }]; #IO_L11N_T1_SRCC_16 Sch=btn[2]
#set_property -dict { PACKAGE_PIN B8    IOSTANDARD LVCMOS33 } [get_ports { btn[3] }]; #IO_L12P_T1_MRCC_16 Sch=btn[3]

## LEDs
# The current percolation_uart_top has no LED debug port.
# If a debug output is added later, constrain it here.


## USB-UART Interface
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_tx_o]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports uart_rx_i]


connect_debug_port u_ila_0/probe0 [get_nets [list {core_cfg_p_s[0]} {core_cfg_p_s[1]} {core_cfg_p_s[2]} {core_cfg_p_s[3]} {core_cfg_p_s[4]} {core_cfg_p_s[5]} {core_cfg_p_s[6]} {core_cfg_p_s[7]} {core_cfg_p_s[8]} {core_cfg_p_s[9]} {core_cfg_p_s[10]} {core_cfg_p_s[11]} {core_cfg_p_s[12]} {core_cfg_p_s[13]} {core_cfg_p_s[14]} {core_cfg_p_s[15]} {core_cfg_p_s[16]} {core_cfg_p_s[17]} {core_cfg_p_s[18]} {core_cfg_p_s[19]} {core_cfg_p_s[20]} {core_cfg_p_s[21]} {core_cfg_p_s[22]} {core_cfg_p_s[23]} {core_cfg_p_s[24]} {core_cfg_p_s[25]} {core_cfg_p_s[26]} {core_cfg_p_s[27]} {core_cfg_p_s[28]} {core_cfg_p_s[29]} {core_cfg_p_s[30]} {core_cfg_p_s[31]}]]
connect_debug_port u_ila_0/probe2 [get_nets [list {core_spanning_s[0]} {core_spanning_s[1]} {core_spanning_s[2]} {core_spanning_s[3]} {core_spanning_s[4]} {core_spanning_s[5]} {core_spanning_s[6]} {core_spanning_s[7]} {core_spanning_s[8]} {core_spanning_s[9]} {core_spanning_s[10]} {core_spanning_s[11]} {core_spanning_s[12]} {core_spanning_s[13]} {core_spanning_s[14]} {core_spanning_s[15]} {core_spanning_s[16]} {core_spanning_s[17]} {core_spanning_s[18]} {core_spanning_s[19]} {core_spanning_s[20]} {core_spanning_s[21]} {core_spanning_s[22]} {core_spanning_s[23]} {core_spanning_s[24]} {core_spanning_s[25]} {core_spanning_s[26]} {core_spanning_s[27]} {core_spanning_s[28]} {core_spanning_s[29]} {core_spanning_s[30]} {core_spanning_s[31]}]]
connect_debug_port u_ila_0/probe3 [get_nets [list {core_cfg_seed_s[0]} {core_cfg_seed_s[1]} {core_cfg_seed_s[2]} {core_cfg_seed_s[3]} {core_cfg_seed_s[4]} {core_cfg_seed_s[5]} {core_cfg_seed_s[6]} {core_cfg_seed_s[7]} {core_cfg_seed_s[8]} {core_cfg_seed_s[9]} {core_cfg_seed_s[10]} {core_cfg_seed_s[11]} {core_cfg_seed_s[12]} {core_cfg_seed_s[13]} {core_cfg_seed_s[14]} {core_cfg_seed_s[15]} {core_cfg_seed_s[16]} {core_cfg_seed_s[17]} {core_cfg_seed_s[18]} {core_cfg_seed_s[19]} {core_cfg_seed_s[20]} {core_cfg_seed_s[21]} {core_cfg_seed_s[22]} {core_cfg_seed_s[23]} {core_cfg_seed_s[24]} {core_cfg_seed_s[25]} {core_cfg_seed_s[26]} {core_cfg_seed_s[27]} {core_cfg_seed_s[28]} {core_cfg_seed_s[29]} {core_cfg_seed_s[30]} {core_cfg_seed_s[31]}]]
connect_debug_port u_ila_0/probe4 [get_nets [list {core_cfg_steps_s[0]} {core_cfg_steps_s[1]} {core_cfg_steps_s[2]} {core_cfg_steps_s[3]} {core_cfg_steps_s[4]} {core_cfg_steps_s[5]} {core_cfg_steps_s[6]} {core_cfg_steps_s[7]} {core_cfg_steps_s[8]} {core_cfg_steps_s[9]} {core_cfg_steps_s[10]} {core_cfg_steps_s[11]} {core_cfg_steps_s[12]} {core_cfg_steps_s[13]} {core_cfg_steps_s[14]} {core_cfg_steps_s[15]}]]
connect_debug_port u_ila_0/probe6 [get_nets [list {core_total_s[0]} {core_total_s[1]} {core_total_s[2]} {core_total_s[3]} {core_total_s[4]} {core_total_s[5]} {core_total_s[6]} {core_total_s[7]} {core_total_s[8]} {core_total_s[9]} {core_total_s[10]} {core_total_s[11]} {core_total_s[12]} {core_total_s[13]} {core_total_s[14]} {core_total_s[15]} {core_total_s[16]} {core_total_s[17]} {core_total_s[18]} {core_total_s[19]} {core_total_s[20]} {core_total_s[21]} {core_total_s[22]} {core_total_s[23]} {core_total_s[24]} {core_total_s[25]} {core_total_s[26]} {core_total_s[27]} {core_total_s[28]} {core_total_s[29]} {core_total_s[30]} {core_total_s[31]}]]
connect_debug_port u_ila_0/probe7 [get_nets [list {rx_msg_latched_s[0]} {rx_msg_latched_s[1]} {rx_msg_latched_s[2]} {rx_msg_latched_s[3]} {rx_msg_latched_s[4]} {rx_msg_latched_s[5]} {rx_msg_latched_s[6]} {rx_msg_latched_s[7]} {rx_msg_latched_s[8]} {rx_msg_latched_s[9]} {rx_msg_latched_s[10]} {rx_msg_latched_s[11]} {rx_msg_latched_s[12]} {rx_msg_latched_s[13]} {rx_msg_latched_s[14]} {rx_msg_latched_s[15]} {rx_msg_latched_s[16]} {rx_msg_latched_s[17]} {rx_msg_latched_s[18]} {rx_msg_latched_s[19]} {rx_msg_latched_s[20]} {rx_msg_latched_s[21]} {rx_msg_latched_s[22]} {rx_msg_latched_s[23]} {rx_msg_latched_s[24]} {rx_msg_latched_s[25]} {rx_msg_latched_s[26]} {rx_msg_latched_s[27]} {rx_msg_latched_s[28]} {rx_msg_latched_s[29]} {rx_msg_latched_s[30]} {rx_msg_latched_s[31]} {rx_msg_latched_s[32]} {rx_msg_latched_s[33]} {rx_msg_latched_s[34]} {rx_msg_latched_s[35]} {rx_msg_latched_s[36]} {rx_msg_latched_s[37]} {rx_msg_latched_s[38]} {rx_msg_latched_s[39]} {rx_msg_latched_s[40]} {rx_msg_latched_s[41]} {rx_msg_latched_s[42]} {rx_msg_latched_s[43]} {rx_msg_latched_s[44]} {rx_msg_latched_s[45]} {rx_msg_latched_s[46]} {rx_msg_latched_s[47]} {rx_msg_latched_s[48]} {rx_msg_latched_s[49]} {rx_msg_latched_s[50]} {rx_msg_latched_s[51]} {rx_msg_latched_s[52]} {rx_msg_latched_s[53]} {rx_msg_latched_s[54]} {rx_msg_latched_s[55]} {rx_msg_latched_s[56]} {rx_msg_latched_s[57]} {rx_msg_latched_s[58]} {rx_msg_latched_s[59]} {rx_msg_latched_s[60]} {rx_msg_latched_s[61]} {rx_msg_latched_s[62]} {rx_msg_latched_s[63]} {rx_msg_latched_s[64]} {rx_msg_latched_s[65]} {rx_msg_latched_s[66]} {rx_msg_latched_s[67]} {rx_msg_latched_s[68]} {rx_msg_latched_s[69]} {rx_msg_latched_s[70]} {rx_msg_latched_s[71]} {rx_msg_latched_s[72]} {rx_msg_latched_s[73]} {rx_msg_latched_s[74]} {rx_msg_latched_s[75]} {rx_msg_latched_s[76]} {rx_msg_latched_s[77]} {rx_msg_latched_s[78]} {rx_msg_latched_s[79]} {rx_msg_latched_s[80]} {rx_msg_latched_s[81]} {rx_msg_latched_s[82]} {rx_msg_latched_s[83]} {rx_msg_latched_s[84]} {rx_msg_latched_s[85]} {rx_msg_latched_s[86]} {rx_msg_latched_s[87]} {rx_msg_latched_s[88]} {rx_msg_latched_s[89]} {rx_msg_latched_s[90]} {rx_msg_latched_s[91]} {rx_msg_latched_s[92]} {rx_msg_latched_s[93]} {rx_msg_latched_s[94]} {rx_msg_latched_s[95]} {rx_msg_latched_s[96]} {rx_msg_latched_s[97]} {rx_msg_latched_s[98]} {rx_msg_latched_s[99]} {rx_msg_latched_s[100]} {rx_msg_latched_s[101]} {rx_msg_latched_s[102]} {rx_msg_latched_s[103]} {rx_msg_latched_s[104]} {rx_msg_latched_s[105]} {rx_msg_latched_s[106]} {rx_msg_latched_s[107]} {rx_msg_latched_s[108]} {rx_msg_latched_s[109]} {rx_msg_latched_s[110]} {rx_msg_latched_s[111]} {rx_msg_latched_s[112]} {rx_msg_latched_s[113]} {rx_msg_latched_s[114]} {rx_msg_latched_s[115]} {rx_msg_latched_s[116]} {rx_msg_latched_s[117]} {rx_msg_latched_s[118]} {rx_msg_latched_s[119]} {rx_msg_latched_s[120]} {rx_msg_latched_s[121]} {rx_msg_latched_s[122]} {rx_msg_latched_s[123]} {rx_msg_latched_s[124]} {rx_msg_latched_s[125]} {rx_msg_latched_s[126]} {rx_msg_latched_s[127]}]]
connect_debug_port u_ila_0/probe11 [get_nets [list core_done_s]]
connect_debug_port u_ila_0/probe12 [get_nets [list core_run_en_s]]

