`timescale 1ns / 1ps

// Data distribution in essence according to flow diagram in Fig. 3 of paper
// 
// Sending direction
// OPT2 (gtp0) to OPT1 (gtp1) goes up/down in x-direction  ATTENTION: order on PCB swapped!!!! 
// OPT3 (gtp2) to OPT4 (gtp3) goes up/down in y-direction
// ETH3 to ETH4 goes up/down in z-direction
//
//-ETH3 and ETH4 work with 1GB/s with overhead 24bytes (8 preamble, 1 seq count, 3 crc, 12 framegap) for 28bytes transmitted
// each 4 bytes (icluding crc and seq count) are extended by 1 additional byte for ECC. Hence, a full data packet needs 60 cycles (ECC might go out, as it is no longer needed)
//-gtp0-gtp3 work with 4 GB/s with overhead 3 words (1 start, 1 crc  + seq count, 1 framegap) for 7 32bit words transmitted.
// A full data packet needs 10 cycles.
//-Sends data directly over all 6 links. In the (xy)-plane, data are distributed in two steps:
// received from gtp0 (x:neg) -> send to gtp2 (y:pos) 
// received from gtp3 (y:pos) -> sedn to gtp0 (x:pos)
// received from gtp1 (x:pos) -> send to gtp3 (y:neg)
// received from gtp2 (y:neg) -> send to gtp1 (x:neg)
// ATTENTION role of gtp0/gtp1 and gtp2/gtp3 swap when considering receiving vs sending
//-In addition, send data received from ETH3 and ETH4 over gtp0-gtp3 to all neighboring nodes in the (xy)-plane according to the 
// same scheme. As a result, ETH3 and ETH4 have to do one trasnmission per atom, while each gtp does 6. Overall times needed for 
// ETH's and gtp's are balanced
//-If DataIn are not in (xyz)-range of homebox, i.e., not in 0<=DataIn<2^22 for either x, y or z, which is the fixed-point 
// equivalent of 0<=DataIn<1, it is not saved into home box. It is however broadcasted over all links, so that it can be saved 
// into home box of the correct neighboring node. Upon receiving data over a link data, whose (xyz)-range is not in 0<x,y,z<=1, 
// it is not saved into the corresponding neighboring neighboring box, but into the home-box, if it is in its range   
//
//-ATTENTION: nomenclature "n" and "p" stands for sending (!) in negative and positive directions, respectively. From the 
// perspective of the MD machine, which receives these data from neighboring nodes, signs will be opposite. 
//
//Braodcast both atom data and ensemble data (such as temperature, etc). The higest byte is an indicator. The lower 6 bit of that byte
//indicate the direction in which data have been sent, and the higest two bits distinguish atom data (2'b00) from ensemble data (2'b01).
//


module BroadcastAtom
#(
parameter DataByteWidth     = 5'd27,
parameter DataByteWidth_n   = 5'd18, 
parameter EnsembleByteWidth = 5'd12,
parameter nBox              = 5'd27
)
(
    input                              IOclk,  
    input                              ErrorReset,
    input                              ResetStart,
//ETH connections
    input                              e3_clk,
    output                             e3_reset,
    output                             e3_tx_en,              //ETH transmit enable
    output [7:0]                       e3_txd,                //ETH transmit data
    input                              e3_rx_dv,              //ETH receive data valid 
    input  [7:0]                       e3_rxd,                //ETH receive data
//    input                              e3_rx_er,            //ETH receive error from PHY
    output                             e3_mdc,                //mdc interface
    inout                              e3_mdio,               //mdio interface
    output [1:0]                       speed3,                //ethernet speed 00: no link, 01: 10M 02:100M 11:1000M
    input                              e4_clk,
    output                             e4_reset,
    output                             e4_tx_en,              //ETH transmit enable
    output [7:0]                       e4_txd,                //ETH transmit data
    input                              e4_rx_dv,              //ETH receive data valid 
    input  [7:0]                       e4_rxd,                //ETH receive data
//    input                              e4_rx_er,            //ETH receive error from PHY
    output                             e4_mdc,                //mdc interface
    inout                              e4_mdio,               //mdio interface
    output [1:0]                       speed4,                //ethernet speed 00: no link, 01: 10M 02:100M 11:1000M
    output [7:0]                       ETH_error,             //={e4_rx_error[2:0],e4_tx_error,e3_rx_error[2:0],e3_tx_error}
    input  [1:0]                       ReNegotiateETH34,      //ReNegotiate ETH-links 3 and 4; in essence no longer needed
//GTP connections
    input                              Q0_CLK0_GTREFCLK_PAD_N_IN,  //GTP clock
    input                              Q0_CLK0_GTREFCLK_PAD_P_IN,  //GTP clock
    input [3:0]                        RXN_IN,                //GTP rx pins
    input [3:0]                        RXP_IN,                //GTP rx pins  
    output[3:0]                        TXN_OUT,               //GTP tx pins
    output[3:0]                        TXP_OUT,               //GTP tx pins
    output[11:0]                       gtp_error,             //={gtp_rx_error,gtp_tx_error}
//input data   
    input                              DataIn_req,            //data to be broadcasted ready
    input  [DataByteWidth*8-1:0]       DataIn,                //data from host PC to be broadcasted
    input  [DataByteWidth*8-1:0]       newData,               //newly calculated data to be broadcasted
    input                              newDataReady,          //newly calculated data ready
    input  [EnsembleByteWidth*8-1:0]   EnsembleData,          //ensemble data such as temperature, etc. 
    input                              EnsembleReady,         //ensemble data ready to broadcast 
    output [EnsembleByteWidth*8-1:0]   EnsembleNeighbor,      //ensemble data such as temperature, etc. received from neighboring box 
    output                             EnsembleNeighborValid, //ensemble data received from neighboring box ready       
//output results
    output reg                         Broadcast_bussy=1'b0,  //transmission bussy signal
    output [nBox-1:0]                  data_valid,            //receiving data valid
    output [DataByteWidth*8-1:0]       DataHome,              //data that go into homebox, valid signal is data_valid[0], included positions, metadata and velocities
    output [DataByteWidth_n*8-1:0]     gtp0_data_recv_short,  //data received from gtp0; data_valid will tell in which box it goes, included positions and metadata, but not velocities
    output [DataByteWidth_n*8-1:0]     gtp1_data_recv_short,  //data received from gtp1; data_valid will tell in which box it goes
    output [DataByteWidth_n*8-1:0]     gtp2_data_recv_short,  //data received from gtp2; data_valid will tell in which box it goes
    output [DataByteWidth_n*8-1:0]     gtp3_data_recv_short,  //data received from gtp3; data_valid will tell in which box it goes
    output [DataByteWidth_n*8-1:0]     e3_data_recv_short,    //data received from eth3; data_valid will tell in which box it goes
    output [DataByteWidth_n*8-1:0]     e4_data_recv_short,    //data received from eth3; data_valid will tell in which box it goes
    output                             GatedMuxError          //fatal overflow error in in one of the GatedMux
);
    
localparam ExtendBussy    =6'd63;   //extend busy signal by 400 ns to bridge gaps  (used to be 30, error, with 63 worked, )
    
wire [2:0] e4_rx_error,e3_rx_error;     
assign     ETH_error={e4_rx_error,e4_tx_error,e3_rx_error,e3_tx_error};    
wire [3:0] gtp_rx_error;
wire [7:0] gtp_tx_error;
assign     gtp_error={gtp_rx_error,gtp_tx_error};
assign     Broadcast_bussy_d0=e3_bussy||e4_bussy||gtp_bussy;
wire       GatedMux1Error, GatedMux2Error, GatedMux3Error;
assign     GatedMuxError=GatedMux1Error||GatedMux2Error||GatedMux3Error;



//extend busy signal by ExtendBussy counts (200ns)
reg  [5:0] DelayBussy_cnt=1'b0;
always @(posedge IOclk) begin
  if(Broadcast_bussy_d0==1'b1) begin
    DelayBussy_cnt  <= 1'b0;
    Broadcast_bussy <= 1'b1;
  end else begin
    if (DelayBussy_cnt<ExtendBussy) DelayBussy_cnt  <= DelayBussy_cnt+1'b1;
    else                            Broadcast_bussy <= 1'b0;
  end  
end

//***************************************************************************************
wire   e3_data_valid;
wire   e4_data_valid;
wire   gtp0_data_valid;
wire   gtp1_data_valid;
wire   gtp2_data_valid;
wire   gtp3_data_valid;

wire [(DataByteWidth+1)*8-1:0]   gtp0_data_recv;
wire [(DataByteWidth+1)*8-1:0]   gtp1_data_recv;
wire [(DataByteWidth+1)*8-1:0]   gtp2_data_recv;
wire [(DataByteWidth+1)*8-1:0]   gtp3_data_recv;
wire [(DataByteWidth+1)*8-1:0]   e3_data_recv;
wire [(DataByteWidth+1)*8-1:0]   e4_data_recv;
assign gtp0_data_recv_short=gtp0_data_recv[DataByteWidth_n*8-1:0];
assign gtp1_data_recv_short=gtp1_data_recv[DataByteWidth_n*8-1:0];
assign gtp2_data_recv_short=gtp2_data_recv[DataByteWidth_n*8-1:0];
assign gtp3_data_recv_short=gtp3_data_recv[DataByteWidth_n*8-1:0];
assign e3_data_recv_short=e3_data_recv[DataByteWidth_n*8-1:0];
assign e4_data_recv_short=e4_data_recv[DataByteWidth_n*8-1:0];
wire [DataByteWidth*8+7:0]       DataSend;
wire                             DataSend_req;

//test whether (xyz) are in range of box
wire [5:0]  dataSign_e3   = {  e3_data_recv[71:70],  e3_data_recv[47:46],  e3_data_recv[23:22]};
wire [5:0]  dataSign_e4   = {  e4_data_recv[71:70],  e4_data_recv[47:46],  e4_data_recv[23:22]};
wire [5:0]  dataSign_gtp0 = {gtp0_data_recv[71:70],gtp0_data_recv[47:46],gtp0_data_recv[23:22]};
wire [5:0]  dataSign_gtp1 = {gtp1_data_recv[71:70],gtp1_data_recv[47:46],gtp1_data_recv[23:22]};
wire [5:0]  dataSign_gtp2 = {gtp2_data_recv[71:70],gtp2_data_recv[47:46],gtp2_data_recv[23:22]};
wire [5:0]  dataSign_gtp3 = {gtp3_data_recv[71:70],gtp3_data_recv[47:46],gtp3_data_recv[23:22]};
wire [5:0]  dataSign_home = {      DataHome[71:70],      DataHome[47:46],      DataHome[23:22]};



wire [5:0]  boxSign_gtp0 = gtp0_data_recv[DataByteWidth*8+:6]|6'b000011;
wire [5:0]  boxSign_gtp1 = gtp1_data_recv[DataByteWidth*8+:6]|6'b000001;
wire [5:0]  boxSign_gtp2 = gtp2_data_recv[DataByteWidth*8+:6]|6'b001100;
wire [5:0]  boxSign_gtp3 = gtp3_data_recv[DataByteWidth*8+:6]|6'b000100;
wire [5:0]  boxSign_e3   = e3_data_recv  [DataByteWidth*8+:6]|6'b110000;
wire [5:0]  boxSign_e4   = e4_data_recv  [DataByteWidth*8+:6]|6'b010000;

//highest two bits = 2'b00 is used as indicator for atom data.
wire        gtp0_data_ind = (gtp0_data_recv[DataByteWidth*8+6+:2]==2'b00);
wire        gtp1_data_ind = (gtp1_data_recv[DataByteWidth*8+6+:2]==2'b00);
wire        gtp2_data_ind = (gtp2_data_recv[DataByteWidth*8+6+:2]==2'b00);
wire        gtp3_data_ind = (gtp3_data_recv[DataByteWidth*8+6+:2]==2'b00);
wire        e3_data_ind   = (e3_data_recv[DataByteWidth*8+6+:2]==2'b00);
wire        e4_data_ind   = (e4_data_recv[DataByteWidth*8+6+:2]==2'b00);

wire [5:0]  EnsembleValid = {(~ResetStart && e4_data_valid   && e4_data_recv[DataByteWidth*8+6+:2]==2'b01),
                             (~ResetStart && e3_data_valid   && e3_data_recv[DataByteWidth*8+6+:2]==2'b01),
                             (~ResetStart && gtp3_data_valid && gtp3_data_recv[DataByteWidth*8+6+:2]==2'b01),
                             (~ResetStart && gtp2_data_valid && gtp2_data_recv[DataByteWidth*8+6+:2]==2'b01),
                             (~ResetStart && gtp1_data_valid && gtp1_data_recv[DataByteWidth*8+6+:2]==2'b01),
                             (~ResetStart && gtp0_data_valid && gtp0_data_recv[DataByteWidth*8+6+:2]==2'b01)
                            };
                       
assign     data_valid={~ResetStart && gtp1_data_ind && gtp1_data_valid && (dataSign_gtp1==6'b0) && (boxSign_gtp1==6'b010101),     //ppp    
                       ~ResetStart && gtp3_data_ind && gtp3_data_valid && (dataSign_gtp3==6'b0) && (boxSign_gtp3==6'b010111),     //ppn                  
                       ~ResetStart && gtp3_data_ind && gtp3_data_valid && (dataSign_gtp3==6'b0) && (boxSign_gtp3==6'b010100),     //pp0                                 
                       ~ResetStart && gtp2_data_ind && gtp2_data_valid && (dataSign_gtp2==6'b0) && (boxSign_gtp2==6'b011101),     //pnp    
                       ~ResetStart && gtp0_data_ind && gtp0_data_valid && (dataSign_gtp0==6'b0) && (boxSign_gtp0==6'b011111),     //pnn    
                       ~ResetStart && gtp2_data_ind && gtp2_data_valid && (dataSign_gtp2==6'b0) && (boxSign_gtp2==6'b011100),     //pn0
                       ~ResetStart && gtp1_data_ind && gtp1_data_valid && (dataSign_gtp1==6'b0) && (boxSign_gtp1==6'b010001),     //p0p
                       ~ResetStart && gtp0_data_ind && gtp0_data_valid && (dataSign_gtp0==6'b0) && (boxSign_gtp0==6'b010011),     //p0n
                       ~ResetStart && e4_data_ind   && e4_data_valid   && (dataSign_e4  ==6'b0) && (boxSign_e4  ==6'b010000),     //p00
                       ~ResetStart && gtp1_data_ind && gtp1_data_valid && (dataSign_gtp1==6'b0) && (boxSign_gtp1==6'b110101),     //npp   
                       ~ResetStart && gtp3_data_ind && gtp3_data_valid && (dataSign_gtp3==6'b0) && (boxSign_gtp3==6'b110111),     //npn   
                       ~ResetStart && gtp3_data_ind && gtp3_data_valid && (dataSign_gtp3==6'b0) && (boxSign_gtp3==6'b110100),     //np0          
                       ~ResetStart && gtp2_data_ind && gtp2_data_valid && (dataSign_gtp2==6'b0) && (boxSign_gtp2==6'b111101),     //nnp   
                       ~ResetStart && gtp0_data_ind && gtp0_data_valid && (dataSign_gtp0==6'b0) && (boxSign_gtp0==6'b111111),     //nnn   
                       ~ResetStart && gtp2_data_ind && gtp2_data_valid && (dataSign_gtp2==6'b0) && (boxSign_gtp2==6'b111100),     //nn0
                       ~ResetStart && gtp1_data_ind && gtp1_data_valid && (dataSign_gtp1==6'b0) && (boxSign_gtp1==6'b110001),     //n0p
                       ~ResetStart && gtp0_data_ind && gtp0_data_valid && (dataSign_gtp0==6'b0) && (boxSign_gtp0==6'b110011),     //n0n
                       ~ResetStart && e3_data_ind   && e3_data_valid   && (dataSign_e3  ==6'b0) && (boxSign_e3  ==6'b110000),     //n00                       
                       ~ResetStart && gtp1_data_ind && gtp1_data_valid && (dataSign_gtp1==6'b0) && (boxSign_gtp1==6'b000101),     //0pp   
                       ~ResetStart && gtp3_data_ind && gtp3_data_valid && (dataSign_gtp3==6'b0) && (boxSign_gtp3==6'b000111),     //0pn                      
                       ~ResetStart && gtp3_data_ind && gtp3_data_valid && (dataSign_gtp3==6'b0) && (boxSign_gtp3==6'b000100),     //0p0                                 
                       ~ResetStart && gtp2_data_ind && gtp2_data_valid && (dataSign_gtp2==6'b0) && (boxSign_gtp2==6'b001101),     //0np   
                       ~ResetStart && gtp0_data_ind && gtp0_data_valid && (dataSign_gtp0==6'b0) && (boxSign_gtp0==6'b001111),     //0nn                      
                       ~ResetStart && gtp2_data_ind && gtp2_data_valid && (dataSign_gtp2==6'b0) && (boxSign_gtp2==6'b001100),     //0n0
                       ~ResetStart && gtp1_data_ind && gtp1_data_valid && (dataSign_gtp1==6'b0) && (boxSign_gtp1==6'b000001),     //00p
                       ~ResetStart && gtp0_data_ind && gtp0_data_valid && (dataSign_gtp0==6'b0) && (boxSign_gtp0==6'b000011),     //00n
                       ~ResetStart && DataHome_req    && (dataSign_home==6'b0)};                                 //000


//***********************************input multiplexer***********************************************
//input multiplexer that sends data from host PC, newly calculated data, or data from neighboring boxes to home box and over network. 
//Data received from neighboring boxes are sent out in case their range is not in the range of the neighboring box but within the home box. 

//shift data from neighboring boxes into home box by zeroing bits [23:22] of xyz-coordinatesd
wire[DataByteWidth*8-1:0]  e3_data_shift   = e3_data_recv[DataByteWidth*8-1:0]   & {{DataByteWidth*8-72{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}}};
wire[DataByteWidth*8-1:0]  e4_data_shift   = e4_data_recv[DataByteWidth*8-1:0]   & {{DataByteWidth*8-72{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}}};
wire[DataByteWidth*8-1:0]  gtp0_data_shift = gtp0_data_recv[DataByteWidth*8-1:0] & {{DataByteWidth*8-72{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}}};
wire[DataByteWidth*8-1:0]  gtp1_data_shift = gtp1_data_recv[DataByteWidth*8-1:0] & {{DataByteWidth*8-72{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}}};
wire[DataByteWidth*8-1:0]  gtp2_data_shift = gtp2_data_recv[DataByteWidth*8-1:0] & {{DataByteWidth*8-72{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}}};
wire[DataByteWidth*8-1:0]  gtp3_data_shift = gtp3_data_recv[DataByteWidth*8-1:0] & {{DataByteWidth*8-72{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}},2'b00,{22{1'b1}}};

wire outOfRange_gtp0 = gtp0_data_valid && gtp0_data_ind && (dataSign_gtp0==boxSign_gtp0); 
wire outOfRange_gtp1 = gtp1_data_valid && gtp1_data_ind && (dataSign_gtp1==boxSign_gtp1);    
wire outOfRange_gtp2 = gtp2_data_valid && gtp2_data_ind && (dataSign_gtp2==boxSign_gtp2);    
wire outOfRange_gtp3 = gtp3_data_valid && gtp3_data_ind && (dataSign_gtp3==boxSign_gtp3);                        
wire outOfRange_e3   = e3_data_valid   &&  e3_data_ind && (dataSign_e3  ==boxSign_e3);     
wire outOfRange_e4   = e4_data_valid   &&  e4_data_ind && (dataSign_e4  ==boxSign_e4);     
 


GatedMultplx
#(
.nPort   (8),
.nByte   (DataByteWidth)                 
) GatedMultplx1
(
 .IOclk             (IOclk),
 .data_port         ({e4_data_shift,e3_data_shift,gtp3_data_shift,gtp2_data_shift,gtp1_data_shift,gtp0_data_shift,newData,DataIn}),
 .tx_req_port       ({outOfRange_e4,outOfRange_e3,outOfRange_gtp3,outOfRange_gtp2,outOfRange_gtp1,outOfRange_gtp0,newDataReady,DataIn_req}),
 .tx_req            (DataHome_req),
 .dataout           (DataHome),
 .error             (GatedMux1Error)
);

//second multiplexer in series combines atom data with ensemble data (such as temperature, etc) for broadcasting. 
//The higest two bits are used as type indicator: 2'b00: atom data; 2'b01: ensemble data
GatedMultplx
#(
.nPort   (2),
.nByte   (DataByteWidth+1)                 
) GatedMultplx2
(
 .IOclk             (IOclk),
 .data_port         ({8'h40,{(DataByteWidth-EnsembleByteWidth)*8{1'b0}},EnsembleData,8'h00,DataHome}),
 .tx_req_port       ({EnsembleReady,DataHome_req}),
 .tx_req            (DataSend_req),
 .dataout           (DataSend),
 .error             (GatedMux2Error)
);

//combines incomig ensemble data from neighboring nodes into one stream for adding them up
GatedMultplx
#(
.nPort   (6),
.nByte   (EnsembleByteWidth)                 
) GatedMultplx3
(
 .IOclk             (IOclk),
 .data_port         ({e4_data_recv[EnsembleByteWidth*8-1:0],e3_data_recv[EnsembleByteWidth*8-1:0],gtp3_data_recv[EnsembleByteWidth*8-1:0],gtp2_data_recv[EnsembleByteWidth*8-1:0],gtp1_data_recv[EnsembleByteWidth*8-1:0],gtp0_data_recv[EnsembleByteWidth*8-1:0]}),
 .tx_req_port       (EnsembleValid),
 .tx_req            (EnsembleNeighborValid),
 .dataout           (EnsembleNeighbor),
 .error             (GatedMux3Error)
);


//******************************************************GTP interfaces************************************************
wire gtp0_valid2 = (gtp0_data_recv[DataByteWidth*8+3:DataByteWidth*8+2]==2'b0)&&gtp0_data_valid;   //check in upper byte if previous transfer in Y has already been done
wire gtp1_valid2 = (gtp1_data_recv[DataByteWidth*8+3:DataByteWidth*8+2]==2'b0)&&gtp1_data_valid;   //do it only once
wire gtp2_valid2 = (gtp2_data_recv[DataByteWidth*8+1:DataByteWidth*8+0]==2'b0)&&gtp2_data_valid;   //check in upper byte if previous transfer in X has already been done
wire gtp3_valid2 = (gtp3_data_recv[DataByteWidth*8+1:DataByteWidth*8+0]==2'b0)&&gtp3_data_valid;   //do it only once

GTP_top 
#(
.nGTP ((DataByteWidth+1)/4)                   //length of data line in units of 32bit
) GTP_top
(
 .IOclk                      (IOclk),  
 .ErrorReset                 (ErrorReset),   
 .gtp_bussy                  (gtp_bussy),                    
//sending part
 .tx0_req_port0              (DataSend_req),       
 .data0_port0                (DataSend), 
 .tx0_req_port1              (gtp3_valid2),       
 .data0_port1                (gtp3_data_recv|{8'b00000100,{DataByteWidth*8{1'b0}}}),    //did y: pos already; now x pos
 .tx0_req_port2              (e3_data_valid),     
 .data0_port2                (e3_data_recv  |{8'b00110000,{DataByteWidth*8{1'b0}}}),    //did z: neg already; now x pos
 .tx0_req_port3              (e4_data_valid),       
 .data0_port3                (e4_data_recv  |{8'b00010000,{DataByteWidth*8{1'b0}}}),    //did z: pos already; now x pos
 
 .tx1_req_port0              (DataSend_req),       
 .data1_port0                (DataSend),
 .tx1_req_port1              (gtp2_valid2),       
 .data1_port1                (gtp2_data_recv|{8'b00001100,{DataByteWidth*8{1'b0}}}),    //did y: neg already; now x neg     
 .tx1_req_port2              (e3_data_valid),       
 .data1_port2                (e3_data_recv  |{8'b00110000,{DataByteWidth*8{1'b0}}}),    //did z: neg already; now x neg
 .tx1_req_port3              (e4_data_valid),       
 .data1_port3                (e4_data_recv  |{8'b00010000,{DataByteWidth*8{1'b0}}}),    //did z: pos already; now x neg
 
 .tx2_req_port0              (DataSend_req),  
 .data2_port0                (DataSend),                
 .tx2_req_port1              (gtp0_valid2),                        
 .data2_port1                (gtp0_data_recv|{8'b00000011,{DataByteWidth*8{1'b0}}}),    //did x: neg already; now y pos
 .tx2_req_port2              (e3_data_valid),       
 .data2_port2                (e3_data_recv  |{8'b00110000,{DataByteWidth*8{1'b0}}}),    //did z: neg already; now y pos
 .tx2_req_port3              (e4_data_valid),       
 .data2_port3                (e4_data_recv  |{8'b00010000,{DataByteWidth*8{1'b0}}}),    //did z: pos already; now y pos
   
 .tx3_req_port0              (DataSend_req),       
 .data3_port0                (DataSend),      
 .tx3_req_port1              (gtp1_valid2),                        
 .data3_port1                (gtp1_data_recv|{8'b00000001,{DataByteWidth*8{1'b0}}}),    //did x: pos already; now y neg
 .tx3_req_port2              (e3_data_valid),       
 .data3_port2                (e3_data_recv  |{8'b00110000,{DataByteWidth*8{1'b0}}}),    //did z: neg already; now y neg
 .tx3_req_port3              (e4_data_valid),       
 .data3_port3                (e4_data_recv  |{8'b00010000,{DataByteWidth*8{1'b0}}}),    //did z: pos already; now y neg
  
 .gtp_tx_error               (gtp_tx_error),     
 
//receiving part
 .data0_recv                 (gtp0_data_recv),        //output [nGTP*32-1:0] compiled received data
 .data0_valid                (gtp0_data_valid),       //output              received data valid
 .data1_recv                 (gtp1_data_recv),        //output [nGTP*32-1:0] compiled received data
 .data1_valid                (gtp1_data_valid),       //output              received data valid  
 .data2_recv                 (gtp2_data_recv),        //output [nGTP*32-1:0] compiled received data
 .data2_valid                (gtp2_data_valid),       //output              received data valid
 .data3_recv                 (gtp3_data_recv),        //output [nGTP*32-1:0] compiled received data
 .data3_valid                (gtp3_data_valid),       //output              received data valid
 .gtp_rx_error               (gtp_rx_error),
//interface part
 .Q0_CLK0_GTREFCLK_PAD_N_IN  (Q0_CLK0_GTREFCLK_PAD_N_IN),
 .Q0_CLK0_GTREFCLK_PAD_P_IN  (Q0_CLK0_GTREFCLK_PAD_P_IN),                                           
 .RXN_IN                     (RXN_IN),
 .RXP_IN                     (RXP_IN),
 .TXN_OUT                    (TXN_OUT),
 .TXP_OUT                    (TXP_OUT)
);


//************ETH3 and ETH4 for fast links to nodes up and down*************************
ETHlink_top 
#(
.nETH (DataByteWidth+1)                       //length of data line
) ETHlink_top3
(
 .e_clk                       (e3_clk),              //input
 .IOclk                       (IOclk),               //input 
 .ErrorReset                  (ErrorReset),
 .e_reset                     (e3_reset), 
//ETH input/output 
 .e_tx_en                     (e3_tx_en),            //output           transmit enable        
 .e_txd                       (e3_txd),              //output [7:0]     transmit data
 .e_rx_dv                     (e3_rx_dv),            //input            receive data valid
 .e_rxd                       (e3_rxd),              //input  [7:0]     receive data
// .e_rx_er                     (e3_rx_er),            //input            receive error from PHY
 .tx_req                      (DataSend_req),        //input            request transmission
 .data_send                   (DataSend),     //input            data to be transmitted
 .data_recv                   (e3_data_recv),        //output [DataByteWidth*8-1:0] compiled received data
 .data_valid                  (e3_data_valid),       //output           received data valid
 .rx_error                    (e3_rx_error),         
 .tx_error                    (e3_tx_error),
 .ETH_bussy                   (e3_bussy),
 .e_mdc                       (e3_mdc),              //output           ETH PHY register clock
 .e_mdio                      (e3_mdio),             //inout            ETH PHY register data
 .speedCombined               (speed3),              //output           ETH speed 00: no link, 01: 10M 02:100M 11:1000M
 .ReNegotiate                 (ReNegotiateETH34[0])  //input           ReNegotiate ETH link
); 


ETHlink_top 
#(
.nETH (DataByteWidth+1)                       //length of data line
) ETHlink_top4
(
 .e_clk                       (e4_clk),              //clk input
 .IOclk                       (IOclk),               //clk input
 .ErrorReset                  (ErrorReset),
 .e_reset                     (e4_reset),   
//ETH input/output 
 .e_tx_en                     (e4_tx_en),            //output           transmit enable        
 .e_txd                       (e4_txd),              //output [7:0]     transmit data
 .e_rx_dv                     (e4_rx_dv),            //input            receive data valid
 .e_rxd                       (e4_rxd),              //input  [7:0]     receive data
// .e_rx_er                     (e4_rx_er),            //input            receive error from PHY
 .tx_req                      (DataSend_req),        //input            request transmission
 .data_send                   (DataSend),            //input            data to be transmitted
 .data_recv                   (e4_data_recv),        //output [DataByteWidth*8-1:0] compiled received data
 .data_valid                  (e4_data_valid),       //output           received data valid
 .rx_error                    (e4_rx_error),         
 .tx_error                    (e4_tx_error),
 .ETH_bussy                   (e4_bussy),
 .e_mdc                       (e4_mdc),              //output           ETH PHY register clock
 .e_mdio                      (e4_mdio),             //inout            ETH PHY register data
 .speedCombined               (speed4),              //output          ETH speed 00: no link, 01: 10M 02:100M 11:1000M
 .ReNegotiate                 (ReNegotiateETH34[1])  //input           ReNegotiate ETH link
); 
    
endmodule
