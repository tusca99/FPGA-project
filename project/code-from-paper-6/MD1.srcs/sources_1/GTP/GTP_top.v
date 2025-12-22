`timescale 1ns / 1ps
//`define SIMULATION     //if defined, gtp_exdes is commented out, data-lines are cross linked, and clocks are taken from Q0_CLK0_GTREFCLK_PAD_P_IN;
                         //works together with  BroadcastAtom_testbench

//use gtp0-gtp3 as 4Gb links to the nodes in the xy plane. 
//for more information on protocol, see gtp_tx and gtp_rx

module GTP_top
#(
parameter nGTP=5'd7
)
(
 input                           IOclk,  
 input                           ErrorReset,
 output                          gtp_bussy, 
//data to be sent; 4 GTP interfaces, each of which has 4 input ports, which are worked off according to their priority
 input                           tx0_req_port0,
 input  [nGTP*32-1:0]            data0_port0,
 input                           tx0_req_port1,
 input  [nGTP*32-1:0]            data0_port1,
 input                           tx0_req_port2,
 input  [nGTP*32-1:0]            data0_port2,
 input                           tx0_req_port3,
 input  [nGTP*32-1:0]            data0_port3,
 input                           tx1_req_port0,
 input  [nGTP*32-1:0]            data1_port0,
 input                           tx1_req_port1,
 input  [nGTP*32-1:0]            data1_port1,
 input                           tx1_req_port2,
 input  [nGTP*32-1:0]            data1_port2,
 input                           tx1_req_port3,
 input  [nGTP*32-1:0]            data1_port3,
 input                           tx2_req_port0,
 input  [nGTP*32-1:0]            data2_port0,
 input                           tx2_req_port1,
 input  [nGTP*32-1:0]            data2_port1,
 input                           tx2_req_port2,
 input  [nGTP*32-1:0]            data2_port2,
 input                           tx2_req_port3,
 input  [nGTP*32-1:0]            data2_port3,
 input                           tx3_req_port0,
 input  [nGTP*32-1:0]            data3_port0,
 input                           tx3_req_port1,
 input  [nGTP*32-1:0]            data3_port1,
 input                           tx3_req_port2,
 input  [nGTP*32-1:0]            data3_port2,
 input                           tx3_req_port3,
 input  [nGTP*32-1:0]            data3_port3,
 output [7:0]                    gtp_tx_error,
//data received 
 output [nGTP*32-1:0]            data0_recv,
 output                          data0_valid,
 output [nGTP*32-1:0]            data1_recv,
 output                          data1_valid,
 output [nGTP*32-1:0]            data2_recv,
 output                          data2_valid,
 output [nGTP*32-1:0]            data3_recv,
 output                          data3_valid,
 output [3:0]                    gtp_rx_error,
//GTP interfaces       
 input                           Q0_CLK0_GTREFCLK_PAD_N_IN,
 input                           Q0_CLK0_GTREFCLK_PAD_P_IN,
 input [3:0]                     RXN_IN, 
 input [3:0]                     RXP_IN,
 output[3:0]                     TXN_OUT,
 output[3:0]                     TXP_OUT
);

assign gtp_rx_error = {rx3_error,rx2_error,rx1_error,rx0_error};
assign gtp_tx_error = {mux3_error,mux2_error,mux1_error,mux0_error,tx3_error,tx2_error,tx1_error,tx0_error};

assign gtp_bussy=tx0_bussy||tx1_bussy||tx2_bussy||tx3_bussy||rx0_bussy||rx1_bussy||rx2_bussy||rx3_bussy;

`ifdef SIMULATION
   wire tx0_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;
   wire rx0_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;
   wire tx1_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;
   wire rx1_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;
   wire tx2_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;
   wire rx2_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;
   wire tx3_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;
   wire rx3_clk = Q0_CLK0_GTREFCLK_PAD_P_IN;

//reg  [15:0]   cntAll=1'b0;
//always @(posedge tx0_clk) cntAll <= cntAll + 1'b1;

   wire[31:0] tx0_data;
   wire[3:0]  tx0_kchar; 
   wire[31:0] tx1_data;
   wire[3:0]  tx1_kchar; 
   wire[31:0] tx2_data;
   wire[3:0]  tx2_kchar;
   wire[31:0] tx3_data;
   wire[3:0]  tx3_kchar;

   wire[31:0] rx0_data =tx1_data;
   //wire[31:0] rx0_data =  (cntAll==16'h15ff) ? tx1_data^32'h00010000: tx1_data;  //mimic transmission error 
   wire[3:0]  rx0_kchar=tx1_kchar;
   wire[31:0] rx1_data =tx0_data;
   wire[3:0]  rx1_kchar=tx0_kchar;
   wire[31:0] rx2_data =tx3_data;
   wire[3:0]  rx2_kchar=tx3_kchar;
   wire[31:0] rx3_data =tx2_data;
   //wire[31:0] rx3_data =  (cntAll==16'h15ff) ? tx3_data^32'h00010000: tx3_data;  //mimic transmission error 
   wire[3:0]  rx3_kchar=tx2_kchar;    
`else
   wire tx0_clk;
   wire gt0_txfsmresetdone;
   wire[31:0] tx0_data;
   wire[3:0] tx0_kchar; 
   wire tx1_clk;
   wire gt1_txfsmresetdone;
   wire[31:0] tx1_data;
   wire[3:0] tx1_kchar; 
   wire tx2_clk;
   wire gt2_txfsmresetdone;
   wire[31:0] tx2_data;
   wire[3:0] tx2_kchar;
   wire tx3_clk;
   wire gt3_txfsmresetdone;
   wire[31:0] tx3_data;
   wire[3:0] tx3_kchar;

   wire rx0_clk;
   wire[31:0] rx0_data;
   wire[3:0] rx0_kchar;
   wire rx1_clk;
   wire[31:0] rx1_data;
   wire[3:0] rx1_kchar; 
   wire rx2_clk;
   wire[31:0] rx2_data;
   wire[3:0] rx2_kchar;
   wire rx3_clk;
   wire[31:0] rx3_data;
   wire[3:0] rx3_kchar;
 `endif

ClkTransfer #(.extend (2)) ClkTransfer0  
(
    .clkIn      (IOclk),
    .clkOut     (tx0_clk),
    .sigIn      (ErrorReset),
    .sigOut     (ErrorReset_tx0)
); 

gtp_tx #(.nGTP (nGTP)) gtp0_tx
(
    .rst          (~gt0_txfsmresetdone||ErrorReset_tx0),
    .tx_clk       (tx0_clk),
    .IOclk        (IOclk),
    .tx_data      (tx0_data),
    .tx_kchar     (tx0_kchar),
    .data_port0   (data0_port0),          
    .tx_req_port0 (tx0_req_port0),    
    .data_port1   (data0_port1),          
    .tx_req_port1 (tx0_req_port1),   
    .data_port2   (data0_port2),          
    .tx_req_port2 (tx0_req_port2),
    .data_port3   (data0_port3),          
    .tx_req_port3 (tx0_req_port3),                  
    .tx_error     (tx0_error),
    .mux_error    (mux0_error),
    .bussy        (tx0_bussy)
);

ClkTransfer #(.extend (2)) ClkTransfer1  
(
    .clkIn      (IOclk),
    .clkOut     (tx1_clk),
    .sigIn      (ErrorReset),
    .sigOut     (ErrorReset_tx1)
); 


gtp_tx #(.nGTP (nGTP)) gtp1_tx
(
    .rst          (~gt1_txfsmresetdone||ErrorReset_tx1),
    .tx_clk       (tx1_clk),
    .IOclk        (IOclk),
    .tx_data      (tx1_data),
    .tx_kchar     (tx1_kchar),
    .data_port0   (data1_port0),          
    .tx_req_port0 (tx1_req_port0),    
    .data_port1   (data1_port1),          
    .tx_req_port1 (tx1_req_port1),   
    .data_port2   (data1_port2),          
    .tx_req_port2 (tx1_req_port2),
    .data_port3   (data1_port3),          
    .tx_req_port3 (tx1_req_port3),                
    .tx_error     (tx1_error),
    .mux_error    (mux1_error),
    .bussy        (tx1_bussy)
);

ClkTransfer #(.extend (2)) ClkTransfer2  
(
    .clkIn      (IOclk),
    .clkOut     (tx2_clk),
    .sigIn      (ErrorReset),
    .sigOut     (ErrorReset_tx2)
); 


gtp_tx #(.nGTP (nGTP)) gtp2_tx
(
    .rst          (~gt2_txfsmresetdone||ErrorReset_tx2),
    .tx_clk       (tx2_clk),
    .IOclk        (IOclk),
    .tx_data      (tx2_data),
    .tx_kchar     (tx2_kchar),
    .data_port0   (data2_port0),          
    .tx_req_port0 (tx2_req_port0),    
    .data_port1   (data2_port1),          
    .tx_req_port1 (tx2_req_port1),   
    .data_port2   (data2_port2),          
    .tx_req_port2 (tx2_req_port2),
    .data_port3   (data2_port3),          
    .tx_req_port3 (tx2_req_port3),             
    .tx_error     (tx2_error),
    .mux_error    (mux2_error),
    .bussy        (tx2_bussy)
);

ClkTransfer #(.extend (2)) ClkTransfer3  
(
    .clkIn      (IOclk),
    .clkOut     (tx3_clk),
    .sigIn      (ErrorReset),
    .sigOut     (ErrorReset_tx3)
); 


gtp_tx #(.nGTP (nGTP)) gtp3_tx
(
    .rst          (~gt3_txfsmresetdone||ErrorReset_tx3),
    .tx_clk       (tx3_clk),
    .IOclk        (IOclk),
    .tx_data      (tx3_data),
    .tx_kchar     (tx3_kchar),
    .data_port0   (data3_port0),          
    .tx_req_port0 (tx3_req_port0),    
    .data_port1   (data3_port1),          
    .tx_req_port1 (tx3_req_port1),   
    .data_port2   (data3_port2),          
    .tx_req_port2 (tx3_req_port2),
    .data_port3   (data3_port3),          
    .tx_req_port3 (tx3_req_port3),                  
    .tx_error     (tx3_error),
    .mux_error    (mux3_error),
    .bussy        (tx3_bussy)
);
 

//******************************receiving**************************** 


gtp_rx #(.nGTP (nGTP)) gtp0_rx                          
(
    .rst                      (ErrorReset),
    .rx_clk                   (rx0_clk),
    .IOclk                    (IOclk),
    .rx_data                  (rx0_data),
    .rx_kchar                 (rx0_kchar),
    .data_recv                (data0_recv),          //output [nGTP*32-1:0] compiled received data
    .data_valid               (data0_valid),        //output              received data valid
    .error                    (rx0_error),          //output              crc error in received data
    .bussy                    (rx0_bussy)
);




gtp_rx #(.nGTP (nGTP)) gtp1_rx                          
(
    .rst                      (ErrorReset),
    .rx_clk                   (rx1_clk),
    .IOclk                    (IOclk),
    .rx_data                  (rx1_data),
    .rx_kchar                 (rx1_kchar),
    .data_recv                (data1_recv),          //output [nGTP*32-1:0] compiled received data
    .data_valid               (data1_valid),        //output              received data valid
    .error                    (rx1_error),             //output              crc error in received data
    .bussy                    (rx1_bussy)
);




gtp_rx #(.nGTP (nGTP)) gtp2_rx                          
(
    .rst                      (ErrorReset),
    .rx_clk                   (rx2_clk),
    .IOclk                    (IOclk),
    .rx_data                  (rx2_data),
    .rx_kchar                 (rx2_kchar),
    .data_recv                (data2_recv),          //output [nGTP*32-1:0] compiled received data
    .data_valid               (data2_valid),        //output              received data valid
    .error                    (rx2_error),             //output              crc error in received data
    .bussy                    (rx2_bussy)
);




gtp_rx #(.nGTP (nGTP)) gtp3_rx                          
(
    .rst                      (ErrorReset),
    .rx_clk                   (rx3_clk),
    .IOclk                    (IOclk),
    .rx_data                  (rx3_data),
    .rx_kchar                 (rx3_kchar),
    .data_recv                (data3_recv),          //output [nGTP*32-1:0] compiled received data
    .data_valid               (data3_valid),        //output              received data valid
    .error                    (rx3_error),          //output              crc error in received data
    .bussy                    (rx3_bussy)
);




//************************************************************************
`ifndef SIMULATION
gtp_exdes gtp_exdes
    (
    .tx0_clk(tx0_clk),
    .gt0_txfsmresetdone(gt0_txfsmresetdone),
    .tx0_data(tx0_data),
    .tx0_kchar(tx0_kchar),   
    .rx0_clk(rx0_clk),
    .rx0_data(rx0_data),
    .rx0_kchar(rx0_kchar),

    .tx1_clk(tx1_clk),
    .gt1_txfsmresetdone(gt1_txfsmresetdone),
    .tx1_data(tx1_data),
    .tx1_kchar(tx1_kchar),   
    .rx1_clk(rx1_clk),
    .rx1_data(rx1_data),
    .rx1_kchar(rx1_kchar),
    
    .tx2_clk(tx2_clk),
    .gt2_txfsmresetdone(gt2_txfsmresetdone),
    .tx2_data(tx2_data),
    .tx2_kchar(tx2_kchar),   
    .rx2_clk(rx2_clk),
    .rx2_data(rx2_data),
    .rx2_kchar(rx2_kchar),
    
    .tx3_clk(tx3_clk),
    .gt3_txfsmresetdone(gt3_txfsmresetdone),
    .tx3_data(tx3_data),
    .tx3_kchar(tx3_kchar),   
    .rx3_clk(rx3_clk),
    .rx3_data(rx3_data),
    .rx3_kchar(rx3_kchar),
                         
    .Q0_CLK0_GTREFCLK_PAD_N_IN(Q0_CLK0_GTREFCLK_PAD_N_IN),
    .Q0_CLK0_GTREFCLK_PAD_P_IN(Q0_CLK0_GTREFCLK_PAD_P_IN),
	.drp_clk(IOclk),                                           
    .RXN_IN(RXN_IN),
    .RXP_IN(RXP_IN),
    .TXN_OUT(TXN_OUT),
    .TXP_OUT(TXP_OUT)
);
`endif

endmodule
