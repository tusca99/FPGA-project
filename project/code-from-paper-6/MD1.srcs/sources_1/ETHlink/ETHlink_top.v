`timescale 1ns / 1ps

//use ETH3 and ETH4 as 1Gb link to the nodes up and down. 
//see ETH_tx and ETH_rx for more information
//currently ETH_tx and ETH_rx contain an ECC for error correction, but that does not seem to be necessary anymore

module ETHlink_top
#(
parameter nETH=5'd28
)
(
    input                        e_clk  ,
    input                        IOclk  , 
    input                        ErrorReset,  
    output                       e_reset,
    output                       e_tx_en,
    output [7:0]                 e_txd, 
    input                        e_rx_dv,
    input  [7:0]                 e_rxd,
 //   input                        e_rx_er,
    input                        tx_req,
    input  [nETH*8-1:0]          data_send,
    output                       data_valid,
    output [nETH*8-1:0]          data_recv,
    output [2:0]                 rx_error,
    output                       tx_error,
    output                       ETH_bussy,   
    output                       e_mdc,            //mdc interface
    inout                        e_mdio,           //mdio interface
    output reg [1:0]             speedCombined,    //ethernet speed 00: no link, 01: 10M 02:100M 11:1000M
    input                        ReNegotiate       //Renegotiate ETH link
    );

assign ETH_bussy=rx_bussy||tx_bussy;

//*******************ETH transmitting part*******************************************  

ClkTransfer #(.extend (2)) ClkTransfer1  //transfer tx_req between clock domains
(
    .clkIn   (IOclk),
    .clkOut  (e_clk),
    .sigIn   (ErrorReset),
    .sigOut  (ErrorReset2)
); 


ETH_tx 
 #(
   .nETH (nETH)  
 ) ETH_tx
(
 .ErrorReset                  (ErrorReset2),
 .e_clk                       (e_clk),              //input
 .IOclk                       (IOclk),
 .e_tx_en                     (e_tx_en),            //output               transmit enable        
 .e_txd                       (e_txd),              //output [7:0]         transmit data
 .data_send                   (data_send),          //input  [nETH*8-1:0], data to be sent
 .tx_req                      (tx_req),              //input
 .tx_error                    (tx_error),
 .bussy                       (tx_bussy)
); 

//*******************ETH receiving part*******************************************  

ETH_rx 
 #(
   .nETH (nETH)  
 ) ETH_rx
(
 .ErrorReset                  (ErrorReset2),
 .e_clk                       (e_clk),              //input
 .IOclk                       (IOclk),
 .e_rx_dv                     (e_rx_dv),            //input               receievd data valid       
 .e_rxd                       (e_rxd),              //input  [7:0]        received data
// .e_rx_er                     (e_rx_er),            //input               receive error from PHY            
 .data_recv                   (data_recv),          //output [nETH*8-1:0] compiled received data
 .data_valid                  (data_valid),         //output              received data valid
 .error                       (rx_error),           //output              {ecc_corr,seq_err,crc error} in received data
 .bussy                       (rx_bussy)
); 


//*******************MDIO register configuration*******************************************  
wire [1:0] speed;
smi_config 
 #(
.REF_CLK                 (100                   ),        //has been 200MHz, but IOclk now is 100MHz
.MDC_CLK                 (500                   )
)
smi_config_inst
(
.clk                    (IOclk                  ),
.e_reset                (e_reset                ),
.mdc                    (e_mdc                  ),
.mdio                   (e_mdio                 ),
.speed                  (speed                  ),
.link                   (link                   ),
.ReNegotiate            (ReNegotiate),
.mode                   (1'b1                   )          //switch off EEE-mode
);  

always @(posedge IOclk) begin 
  speedCombined <= link ? (speed+2'b01): 2'b00;        
end
   
    
endmodule
