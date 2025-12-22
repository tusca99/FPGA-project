
module MD   
(   
input                           sys_clk_p,                    //system clock positive
input                           sys_clk_n,                    //system clock negative 
//input                           rstExt,                        //reset ,low active
output[1:0]                     led,                          //display network rate status
output                          ledFPGA, 
input                           key1,                         //push botton
input [7:0]                     DipSwitch,      
input                           Fan,     
inout                           AllBussyExt11,   
inout                           errorRxSyncExt11,  
inout                           AllBussyExt12,   
inout                           errorRxSyncExt12,   
inout                           AllBussyExt2,   
inout                           errorRxSyncExt2,       

//ethernet 1
output                          e1_reset,                     //phy reset
output                          e1_mdc,                       //phy emdio clock
inout                           e1_mdio,                      //phy emdio data
input	                        e1_rx_clk_from_pins,          //ethernet rx clock
input                           e1_rx_dv_from_pins,           //recieving data valid
//input                           e1_rx_er,                   //recieving data error
input [7:0]                     e1_rxd_from_pins,             //recieving data          
output                          e1_tx_clk_to_pins,            //gmii tx clock  
output                          e1_tx_en_to_pins,             //ethernet sending data valid  
output                          e1_tx_er,                     //ethernet error    
output[7:0]                     e1_txd_to_pins,               //ethernet sending data 

//ethernet 3
output                          e3_reset,                      //phy reset
output                          e3_mdc,                        //phy emdio clock
inout                           e3_mdio,                       //phy emdio data
input	                        e3_rx_clk_from_pins,           //ethernet rx clock
input                           e3_rx_dv_from_pins,            //recieving data valid
//input                           e3_rx_er,                    //recieving data error
input [7:0]                     e3_rxd_from_pins,              //recieving data          
output                          e3_tx_clk_to_pins,             //gmii tx clock  
output                          e3_tx_en_to_pins,              //ethernet sending data valid    
output                          e3_tx_er,                      //ethernet error
output[7:0]                     e3_txd_to_pins,                //ethernet sending data 

//ethernet 4
output                          e4_reset,                      //phy reset
output                          e4_mdc,                        //phy emdio clock
inout                           e4_mdio,                       //phy emdio data
input	                        e4_rx_clk_from_pins,           //ethernet rx clock
input                           e4_rx_dv_from_pins,            //recieving data valid
//input                           e4_rx_er,                    //recieving data error
input [7:0]                     e4_rxd_from_pins,              //recieving data          
output                          e4_tx_clk_to_pins,             //gmii tx clock  
output                          e4_tx_en_to_pins,              //ethernet sending data valid    
output                          e4_tx_er,                      //ethernet error
output[7:0]                     e4_txd_to_pins,                //ethernet sending data 

//GTP interfaces
output[3:0]                     gtp_tx_disable,        
input                           Q0_CLK0_GTREFCLK_PAD_N_IN,
input                           Q0_CLK0_GTREFCLK_PAD_P_IN,
input [3:0]                     RXN_IN, 
input [3:0]                     RXP_IN,
output[3:0]                     TXN_OUT,
output[3:0]                     TXP_OUT
);  

//(* MARK_DEBUG="true" *)

parameter DataByteWidth     = 27;      //width of data buses, e.g. 3*24bit to describe atom meta data, (xyz) coordinates and xyz velocities
parameter DataByteWidth_n   = 18;      //reduced data width of neigboring boxes, without velocities
parameter EnsembleByteWidth = 5'd12; //width of ensemble data
parameter nBlock            = 50;      //length of a block to be sent at once by UDP; maximum is 534
parameter nBox              = 5'd27;   //number of neigboring boxes together with home box
parameter ForceLUTWidth     = 9;       //length of Force LUT data line
parameter Version           = 8'd6;

//************************************wire connecting sub-modules**************************************************
 wire [7:0]                     PacketNr,PacketNrOld;
 wire [DataByteWidth*8-1:0]     DataIn;
 wire [DataByteWidth*8-1:0]     DataHome;
// wire                           WriteIn_req;
 wire                           nAtomReset;
 wire [47:0]                    errorAll;
 wire [1:0]                     speed1, speed3, speed4;  
 wire [nBox*8-1:0]              nAtom;
 wire [nBox-1:0]                data_valid;
 wire [7:0]                     ETH_error;
 wire [11:0]                    gtp_error;
 wire [DataByteWidth_n*8-1:0]   e3_data_recv,e4_data_recv;
 wire [DataByteWidth_n*8-1:0]   gtp0_data_recv,gtp1_data_recv,gtp2_data_recv,gtp3_data_recv;
 reg                            fan_error=1'b0;    
 reg                            ResetStart=1'b1;
 wire                           Broadcast_bussy;
 wire                           MDReset;
 
 wire [7:0]                     SendMacAdr;
 wire [DataByteWidth*8-1:0]     DataSendMac;
 wire [5:0]                     SendMacBox;
 wire                           StartMac;
 wire [7:0]                     nSendMac;
 
 wire [15:0]                    nstep;
 wire [15:0]                    istep;
 wire                           InitCalc;
 wire                           CalcBussy;
 wire                           SyncOut;
 wire [DataByteWidth*8-1:0]     newData;
 wire                           newDataReady;
 wire                           AllBussyIn;
 wire                           errorRxReset;    
 wire                           errorRxSync;
 wire [79:0]                    errorRxCnt;
 wire                           errorRxSyncIn;
 wire [2:0]                     overflowError;
 //wire [1:0]                     ReNegotiateETH34;
 wire                           wrForceLUT;    
 wire [ForceLUTWidth*8-1:0]     dataForceLUT;  
 wire [8:0]                     adrForceLUT;   
 wire                           selForceLUT;    
 assign                         gtp_tx_disable = 4'b0;
 
 wire [EnsembleByteWidth*8-1:0] EnsembleData;           //Ensemble daa such as temperature, etc. 
 wire                           EnsembleReady;                       
 wire [EnsembleByteWidth*8-1:0] EnsembleNeighbor;
 wire                           EnsembleNeighborValid;
 
 wire                           vcm_shiftOn;          
 wire                           T_scaleOn;             
 wire [23:0]                    T_target;              
 wire [3:0]                     T_scaleTau;       
 
 wire [2:0]                     ReNegotiateETH341;
 wire [10:0]                    CommandCnt;
 wire                           CommandValid;
 wire [7:0]                     CommandData;     
 
 
//****************************************clocks****************************************
clk_wiz_0 clkGeneration
   (
    .clk_out1(CalcClk),     // for claculations, 300MHz
    .clk_out2(IOclk),       // for IO, 100MHz
    .clk_out3(clk200MHz),   // for IDELAYCTRL, 200MHz
    .reset(1'b0),           // input reset
    .clk_in1_p(sys_clk_p),  // input clk_in1_p
    .clk_in1_n(sys_clk_n)   // input clk_in1_n
);




//*************************************ETH ports *****************************************

IDELAYCTRL IDELAYCTRL_inst     //needed for the delays in the ports
(
   .RDY(),          // 1-bit output: Ready output
   .REFCLK(clk200MHz), // 1-bit input: Reference clock input
   .RST(1'b0)        // 1-bit input: Active high reset input
);

 
assign        e1_tx_er       = 1'b0;
assign        e3_tx_er       = 1'b0;
assign        e4_tx_er       = 1'b0;
wire   [7:0]  e1_txd;
wire          e1_tx_en;
wire   [7:0]  e1_rxd;       
wire          e1_rx_dv;
wire   [7:0]  e3_txd;
wire          e3_tx_en;
wire   [7:0]  e3_rxd;       
wire          e3_rx_dv;
wire   [7:0]  e4_txd;
wire          e4_tx_en;
wire   [7:0]  e4_rxd;       
wire          e4_rx_dv;
 
 
ETH_IOport ETH1_IOport
(
  .e_rx_clk_from_pins   (e1_rx_clk_from_pins),  // Single ended clock input from PHY 
  .e_tx_clk_to_pins     (e1_tx_clk_to_pins),    //forwarded clk signal for PHY tx
  .e_clk                (e1_clk),               //internal eth clk 
  .e_rxd_from_pins      (e1_rxd_from_pins),
  .e_rxd                (e1_rxd),
  .e_rx_dv_from_pins    (e1_rx_dv_from_pins),
  .e_rx_dv              (e1_rx_dv),
  .e_txd                (e1_txd),
  .e_txd_to_pins        (e1_txd_to_pins),
  .e_tx_en              (e1_tx_en),
  .e_tx_en_to_pins      (e1_tx_en_to_pins)
); 

ETH_IOport ETH3_IOport
(
  .e_rx_clk_from_pins   (e3_rx_clk_from_pins),  // Single ended clock input from PHY 
  .e_tx_clk_to_pins     (e3_tx_clk_to_pins),    //forwarded clk signal for PHY tx
  .e_clk                (e3_clk),               //internal eth clk 
  .e_rxd_from_pins      (e3_rxd_from_pins),
  .e_rxd                (e3_rxd),
  .e_rx_dv_from_pins    (e3_rx_dv_from_pins),
  .e_rx_dv              (e3_rx_dv),
  .e_txd                (e3_txd),
  .e_txd_to_pins        (e3_txd_to_pins),
  .e_tx_en              (e3_tx_en),
  .e_tx_en_to_pins      (e3_tx_en_to_pins)
);

ETH_IOport ETH4_IOport
(
  .e_rx_clk_from_pins   (e4_rx_clk_from_pins),  // Single ended clock input from PHY 
  .e_tx_clk_to_pins     (e4_tx_clk_to_pins),    //forwarded clk signal for PHY tx
  .e_clk                (e4_clk),               //internal eth clk 
  .e_rxd_from_pins      (e4_rxd_from_pins),
  .e_rxd                (e4_rxd),
  .e_rx_dv_from_pins    (e4_rx_dv_from_pins),
  .e_rx_dv              (e4_rx_dv),
  .e_txd                (e4_txd),
  .e_txd_to_pins        (e4_txd_to_pins),
  .e_tx_en              (e4_tx_en),
  .e_tx_en_to_pins      (e4_tx_en_to_pins)
);
              
//*****************************************1s-clock********************************
 reg  [25:0]  clk_1s_cnt=1'b0;
 reg  [1:0]   fan2      =1'b0;
 reg  [7:0]   fan_cnt   =1'b0;
 reg  [3:0]   Reset_cnt =1'b0;
 always @(posedge IOclk) begin 
   clk_1s_cnt <= clk_1s_cnt +1'b1;
   if(clk_1s_cnt==0) begin
     if (Reset_cnt<4'hf) begin
       Reset_cnt  <= Reset_cnt +1'b1;
       ResetStart <= 1'b1;               //is on for ca 10s
     end else ResetStart <= 1'b0;       
   end
   if(clk_1s_cnt[17:0]==1'b0) begin
     fan2 <= {fan2[0],Fan};
     if((fan2==2'b01)||(fan2==2'b10)) begin
       fan_cnt   <= 1'b0;
       fan_error <= 1'b0;
     end else begin
       if(fan_cnt<8'd200) fan_cnt <= fan_cnt + 1'b1;
       else               fan_error <= 1'b1;
     end
   end
 end     
 assign ledFPGA= (ResetStart||CalcBussy) ? clk_1s_cnt[23] : clk_1s_cnt[25];    
             

            
/******************************************************************************/
MDmachine
#(
.DataByteWidth     (DataByteWidth),
.DataByteWidth_n   (DataByteWidth_n),
.EnsembleByteWidth (EnsembleByteWidth),
.ForceLUTWidth     (ForceLUTWidth),
.nBox              (nBox)
) MDmachine
(
 .IOclk                 (IOclk),  
 .CalcClk               (CalcClk),
 .MDReset               (MDReset),
//inputs from BraodcastAtom to write data into boxes         
 .data_valid            (data_valid),     
 .DataHome              (DataHome),      
 .gtp0_data_recv        (gtp0_data_recv), 
 .gtp1_data_recv        (gtp1_data_recv), 
 .gtp2_data_recv        (gtp2_data_recv), 
 .gtp3_data_recv        (gtp3_data_recv), 
 .e3_data_recv          (e3_data_recv),   
 .e4_data_recv          (e4_data_recv),    
 .overflowError         (overflowError),
//input that writes into Force LUTs 
 .wrForceLUT            (wrForceLUT),    
 .dataForceLUT          (dataForceLUT),  
 .adrForceLUT           (adrForceLUT),   
 .selForceLUT           (selForceLUT),    
//input/output for MD claculation
 .nAtom0                (nAtom),           //on  IOclk              
 .nAtomResetExt         (nAtomReset),  
 .AllBussy              (AllBussyIn), 
 .InitCalc              (InitCalc),
 .nstep                 (nstep), 
 .istepOut              (istep),    
 .SyncOut               (SyncOut),               
 .CalcBussy             (CalcBussy),       
 .errorRxReset          (errorRxReset),    
 .errorRxSync           (errorRxSyncIn),            
 .newData               (newData),
 .newDataReady          (newDataReady),
 .EnsembleData          (EnsembleData),
 .EnsembleReady         (EnsembleReady),
 .EnsembleNeighbor      (EnsembleNeighbor),
 .EnsembleNeighborValid (EnsembleNeighborValid),
//Control inputs for thermostat, etc. 
 .vcm_shiftOn           (vcm_shiftOn),            //center-of-mass velocity shift on/off
 .T_scaleOn             (T_scaleOn),              //velocity scaling thermostat on/off 
 .T_target              (T_target),               //invers target temperature; e.g., T_target=24'h1948B1 is the inverse of T=24'h0a2000
 .T_scaleTau            (T_scaleTau),             //2^n*dt determines time constant of termostat  
//input/output to write content of boxes to MAC    
 .SendMacAdr            (SendMacAdr),   
 .SendMacBox            (SendMacBox),
 .DataSendMac           (DataSendMac)
);

 
 
/***************************************************Broadcast atom data*******************************************************************/

BroadcastAtom
#(
.DataByteWidth     (DataByteWidth),
.DataByteWidth_n   (DataByteWidth_n),
.EnsembleByteWidth (EnsembleByteWidth),
.nBox              (nBox)
) BroadcastAtom
(
    .IOclk                       (IOclk),  
    .ErrorReset                  (ErrorReset),
    .ResetStart                  (ResetStart),
//ETH connections
    .e3_clk                      (e3_clk), 
    .e3_reset                    (e3_reset),
    .e3_tx_en                    (e3_tx_en),          //ETH transmit enable
    .e3_txd                      (e3_txd),            //ETH transmit data
    .e3_rx_dv                    (e3_rx_dv),          //ETH receive data valid 
 //  .e3_rx_er                    (e3_rx_er),          //ETH receive error from PHY
    .e3_rxd                      (e3_rxd),            //ETH receive data
    .e3_mdc                      (e3_mdc),            //mdc interface
    .e3_mdio                     (e3_mdio),           //mdio interface
    .speed3                      (speed3),            //ethernet speed 00: no link, 01: 10M 02:100M 11:1000M
    .e4_clk                      (e4_clk),
    .e4_reset                    (e4_reset),
    .e4_tx_en                    (e4_tx_en),          //ETH transmit enable
    .e4_txd                      (e4_txd),            //ETH transmit data
    .e4_rx_dv                    (e4_rx_dv),          //ETH receive data valid 
    .e4_rxd                      (e4_rxd),            //ETH receive data
  //  .e4_rx_er                    (e4_rx_er),          //ETH receive error from PHY
    .e4_mdc                      (e4_mdc),            //mdc interface
    .e4_mdio                     (e4_mdio),           //mdio interface
    .speed4                      (speed4),            //ethernet speed 00: no link, 01: 10M 02:100M 11:1000M
    .ETH_error                   (ETH_error),         //={e4_rx_error[2:0],e4_tx_error,e3_rx_error[2:0],e3_tx_error}
    .ReNegotiateETH34            (ReNegotiateETH341[1:0]),
//GTP connections
    .Q0_CLK0_GTREFCLK_PAD_N_IN   (Q0_CLK0_GTREFCLK_PAD_N_IN),  //GTP clock
    .Q0_CLK0_GTREFCLK_PAD_P_IN   (Q0_CLK0_GTREFCLK_PAD_P_IN),  //GTP clock
    .RXN_IN                      (RXN_IN),           //GTP rx pins
    .RXP_IN                      (RXP_IN),           //GTP rx pins  
    .TXN_OUT                     (TXN_OUT),          //GTP tx pins
    .TXP_OUT                     (TXP_OUT ),         //GTP tx pins
    .gtp_error                   (gtp_error),        //={gtp_rx_error,gtp_tx_error}
//inputs   
    .DataIn_req                  (DataIn_req),       //data from PC to be broadcasted ready    
    .DataIn                      (DataIn),           //data to be broadcasted          
    .newData                     (newData),          //newly claculated data
    .newDataReady                (newDataReady),
    .EnsembleData                (EnsembleData),
    .EnsembleReady               (EnsembleReady),
    .EnsembleNeighbor            (EnsembleNeighbor),
    .EnsembleNeighborValid       (EnsembleNeighborValid),
//output results
    .Broadcast_bussy             (Broadcast_bussy),
    .data_valid                  (data_valid),
    .DataHome                    (DataHome), 
    .gtp0_data_recv_short        (gtp0_data_recv),
    .gtp1_data_recv_short        (gtp1_data_recv),
    .gtp2_data_recv_short        (gtp2_data_recv),
    .gtp3_data_recv_short        (gtp3_data_recv),
    .e3_data_recv_short          (e3_data_recv),
    .e4_data_recv_short          (e4_data_recv),
    .GatedMuxError               (GatedMuxError)
);

/***********************************Communication with host PC via ETH1**********************************************/

wire [DataByteWidth*8-1:0] statusLine={16'b0,EnsembleData[23:0],istep,3'b0,AllBussyIn,SyncOut,CalcBussy,Broadcast_bussy,(CalcBussy|Broadcast_bussy),errorRxCnt,errorAll,Version,PacketNrOld,PacketNr};  //has space for many more information

 mac_top 
#(
.DataByteWidth (DataByteWidth),
.nBlock        (nBlock)
) mac1
(
 .e_clk                       (e1_clk),      
 .IOclk                       (IOclk),
 .CalcClk                     (CalcClk),  
 .e_reset                     (e1_reset),  
 .ResetStart                  (ResetStart),
//IP-stuff 
 .local_mac_addr              ({40'h00_0a_35_01_fe,DipSwitch}),   //local mac address
 .local_ip_addr               ({24'hc0a801,DipSwitch}),           //local 192.168.1.*
 .local_udp_port              (16'h1f90),                //local udp port
//ETH input/output 
 .e_tx_en                     (e1_tx_en),                //output                       transmit enable        
 .e_txd                       (e1_txd),                  //output [7:0]                 transmit data
 .e_rx_dv                     (e1_rx_dv),                //input                        ETH receive data valid
 .e_rxd                       (e1_rxd),                  //input  [7:0]                 ETH receive data
 .e_mdc                       (e1_mdc),                  //output                       ETH PHY register clock
 .e_mdio                      (e1_mdio),                 //inout                        ETH PHY register data
 .speedCombined               (speed1),                  //output                       ETH speed 00: no link, 01: 10M 02:100M 11:1000M
//udp sending part 
 .statusLine                  (statusLine),              //input [DataByteWidth*8-1:0]  statusline
 .nAtom                       (nAtom),                   //input [DataByteWidth*8-1:0]  nAtom's of all boxes 
 .StartMac                    (StartMac),       
 .nSend                       (nSendMac),              
 .DataSendMac                 (DataSendMac),             //input [DataByteWidth*8-1:0]  actual data, to be read from BRAM
 .SendMacAdr                  (SendMacAdr),              //output[7:0]                  address of BRAM to read data
//UDP receiving part
 .ReNegotiateETH1             (ReNegotiateETH341[2]),    //that is new
 .CommandCnt                  (CommandCnt),                  
 .CommandData                 (CommandData),                
 .CommandValid                (CommandValid)        
/*
 .PacketNr                    (PacketNr),                //output [7:0]                 packet number 
 .PacketNrOld                 (PacketNrOld),             //output [7:0]                 previouusly received packet number; to see if packest have been lost
 .WriteDataAtom               (DataIn_req),              //output                       write data into BRAM
 .DataAtom                    (DataIn),                  //output [DataByteWidth*8-1:0] data to be written into BRAM
 .SendMacBox                  (SendMacBox),              //output [6:0]                 select box memory  
 .SendMem                     (StartMac),     
 .nSendMem                    (nSendMac),     
 .nAtomReset                  (nAtomReset),              //output                       reset nAtom counts
 .ErrorReset                  (ErrorReset),              //output                       reset Errors
 .MDReset                     (MDReset),                 //output                       reset MD machine
 .ReNegotiateETH34            (ReNegotiateETH34),
 .InitCalc                    (InitCalc),
 .nstep                       (nstep),
 .wrForceLUT                  (wrForceLUT),    
 .dataForceLUT                (dataForceLUT),  
 .adrForceLUT                 (adrForceLUT),   
 .selForceLUT                 (selForceLUT),     
 .vcm_shiftOn                 (vcm_shiftOn),            //center-of-mass velocity shift on/off
 .T_scaleOn                   (T_scaleOn),              //velocity scaling thermostat on/off 
 .T_target                    (T_target),               //invers target temperature; e.g., T_target=24'h1948B1 is the inverse of T=24'h0a2000
 .T_scaleTau                  (T_scaleTau)              //2^n*dt determines time constant of termostat  
*/ 
);

//********************************************read and interpret input commands***********************

ReadCommand
#(
.DataByteWidth (DataByteWidth),
.ForceLUTWidth (ForceLUTWidth)
) ReadCommand
(  
 .IOclk                       (IOclk),   
 .ResetStart                  (ResetStart),
//in/output to mac_top 
 .CommandCnt                  (CommandCnt),
 .CommandData                 (CommandData),
 .CommandValid                (CommandValid),
//data that are sent higher up 
 .PacketNr                    (PacketNr),                //output [7:0]                 packet number 
 .PacketNrOld                 (PacketNrOld),             //output [7:0]                 previouusly received packet number; to see if packest have been lost
//for command 0: status and reset
 .nAtomReset                  (nAtomReset),              //output                       reset nAtom counts
 .ErrorReset                  (ErrorReset),              //output                       reset Errors
 .MDReset                     (MDReset),                 //output                       reset MD machine
 .ReNegotiateETH341           (ReNegotiateETH341),
//for command 1: initiate MD  
 .InitCalc                    (InitCalc),
 .nstep                       (nstep),
//for command 2: write Force LUTs
 .wrForceLUT                  (wrForceLUT),    
 .dataForceLUT                (dataForceLUT),  
 .adrForceLUT                 (adrForceLUT),   
 .selForceLUT                 (selForceLUT),    
//for command 3: Thermotstat control etc. 
 .vcm_shiftOn                 (vcm_shiftOn),            //center-of-mass velocity shift on/off
 .T_scaleOn                   (T_scaleOn),              //velocity scaling thermostat on/off 
 .T_target                    (T_target),               //invers target temperature; e.g., T_target=24'h1948B1 is the inverse of T=24'h0a2000
 .T_scaleTau                  (T_scaleTau),              //2^n*dt determines time constant of termostat  
//for command 5:  receiving atom data    
 .WriteDataAtom               (DataIn_req),              //output                       write data into BRAM
 .DataAtom                    (DataIn),                  //output [DataByteWidth*8-1:0] data to be written into BRAM
//for command 8: send atom data 
 .SendMacBox                  (SendMacBox),              //output [6:0]                 select box memory
 .nSend                       (nSendMac),
 .SendMem                     (StartMac)
);

/***************************************Synchrinisation of Nodes via 10pin interface******************************************/
SyncNodes SyncNodes
(
.IOclk            (IOclk),
.AllBussyExt11    (AllBussyExt11),   
.errorRxSyncExt11 (errorRxSyncExt11), 
.AllBussyExt12    (AllBussyExt12),   
.errorRxSyncExt12 (errorRxSyncExt12), 
.AllBussyExt2     (AllBussyExt2),   
.errorRxSyncExt2  (errorRxSyncExt2), 
.AllBussy         (SyncOut||Broadcast_bussy),
.errorRxSync      (errorRxSync),
.AllBussyIn       (AllBussyIn),
.errorRxSyncIn    (errorRxSyncIn)
);




//*************************************Error Handler**************************** 
ErrorHandler ErrorHandler
    (
    .clk                (IOclk),
    .error_reset        (ErrorReset||(~key1)),  
    .errorRxReset       (errorRxReset),  
    .ReNegotiateETH34   (ReNegotiateETH341[1:0]),   
    .fan_error          (fan_error),
    .speed3             (speed3),
    .speed4             (speed4),
    .ETH_error          (ETH_error),
    .gtp_error          (gtp_error),
    .GatedMuxError      (GatedMuxError),
    .overflowError      (overflowError),
    .errorAll           (errorAll), 
    .errorRxSync        (errorRxSync),   
    .errorRxCnt         (errorRxCnt)  
    );
    
//*************************************LEDs as error indicator*********************************
assign led =~{|errorAll,(speed1==2'b11)};

endmodule