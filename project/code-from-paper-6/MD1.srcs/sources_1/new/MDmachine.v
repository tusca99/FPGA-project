`timescale 1ns / 1ps
//MD Machine, in essence Fig. 7 of the paper
//- Statemachine CalcState1 (on IPclk): is initiated by InitCalc and loops over time steps, taking care of all synchronisation, etc. Also 
//  initiates HomeState and waits for the completion of all force calculations. 
//  
//- Statemachine HomeState (on CalcClk): is initiated by statemachine CalcState1 For th emost part, loops over atom i1 as well as atom i2
//  in the home box to add up forces from within the homebox. In addition, start_i2 initiates force pipleines concerning the neigboring boxes, 
//  performed in ForceBox_*. 
//
//- Statemachine CalcState2:  collects all forces, and updates velocities as well as positions 
//
//Synchronisation
//- SyncOut and CalcBussy are indicator of the status of the MD machine.
//  SyncOut is for the synchronisation of all nodes: SyncOut is 1 during idele times, switches to 0 to initiate sync, and switches back 
//  to 1 once calculation starts. It goes to 0 when a MD step is completed for re-synchronisation of all nodes. 
//- CalcBussy is 0 in idle, and switches to 1 during whole calculation.  It is used to switch the access to the box memories. In addition
//  it is output on the status line.  



module MDmachine
#(
parameter DataByteWidth     = 5'd27,   //full data width of home box, including velocities 
parameter DataByteWidth_n   = 5'd18,   //reduced data width of neigboring boxes, without velocities
parameter EnsembleByteWidth = 5'd12,
parameter nBox              = 5'd27,
parameter v_shift           = 5,     //velocities shifted down by 4 bit relative to position, +1 extra bit since positions are defined in range +/-2
parameter ForceLUTWidth     = 9      //length of Force LUT data line
)
(
 input                                IOclk,  
 input                                CalcClk,
 input                                MDReset,
//inputs from BraodcastAtom to write data into boxes
 input      [nBox-1:0]                data_valid,             //data valid for homebox or one of the neigboring boxes
 input      [DataByteWidth*8-1:0]     DataHome,               //actual data from the various sources, see BroadcastAtom for details
 input      [DataByteWidth_n*8-1:0]   gtp0_data_recv, 
 input      [DataByteWidth_n*8-1:0]   gtp1_data_recv, 
 input      [DataByteWidth_n*8-1:0]   gtp2_data_recv, 
 input      [DataByteWidth_n*8-1:0]   gtp3_data_recv, 
 input      [DataByteWidth_n*8-1:0]   e3_data_recv,
 input      [DataByteWidth_n*8-1:0]   e4_data_recv,
 output     [2:0]                     overflowError,          //overflow error in one of the boxes or subboxes
 //input that writes into Force LUT; is funneld trhough into ForceNonBond and ForceBox_*
 input                                wrForceLUT,    
 input      [ForceLUTWidth*8-1:0]     dataForceLUT,  
 input      [8:0]                     adrForceLUT,   
 input                                selForceLUT,   
 //input/output for MD claculation
 output     [nBox*8-1:0]              nAtom0,                 //output only for lower half of memory, for status line; on IOClk
 input                                nAtomResetExt,          //reset nAtom counter
 input                                AllBussy,               //some of the other nodes or broadcasting still busy
 input                                InitCalc,               //initiate simulation
 input      [15:0]                    nstep,                  //number of timesteps
 output reg [15:0]                    istepOut,               //istep for status line; is not reset after run 
 output reg                           SyncOut,                //for synchronosation with other nodes
 output reg                           CalcBussy,              //bussy signal for controlling access to box BRAMs and for status line
 output reg                           errorRxReset,           //reset communication error since MD step is repeated
 input                                errorRxSync,            //sync communication error with other nodes
 output reg [DataByteWidth*8-1:0]     newData,                //new atom data
 output reg                           newDataReady,           //new atom data ready for broadcast
 output     [EnsembleByteWidth*8-1:0] EnsembleData,           //ensemble data such as temperature, etc
 output reg                           EnsembleReady=1'b0,     //ensemble data ready for broadcast
 input      [EnsembleByteWidth*8-1:0] EnsembleNeighbor,       //ensemble data from neigboring boxes
 input                                EnsembleNeighborValid,  //ensemble data from neigboring boxes ready   
//Control inputs for thermostat, etc.           
 input                                vcm_shiftOn,           //center-of-mass velocity shift on/off
 input                                T_scaleOn,             //velocity scaling thermostat on/off 
 input      [23:0]                    T_target,              //invers target temperature; e.g., T_target=24'h1948B1 is the inverse of T=24'h0a2000
 input      [3:0]                     T_scaleTau,            //2^n*dt determines time constant of termostat 
//input/output to write content of boxes to MAC, processed in mac_top 
 input      [7:0]                     SendMacAdr,
 input      [5:0]                     SendMacBox,
 output reg [DataByteWidth*8-1:0]     DataSendMac
);

localparam           latHomeBram  = 3;                    //Bram itself has latency 2, plus multiplexer for address
localparam           nPipeForce   = 19;                   //latency of ForceNonBond;
localparam           nPipe_AddFtot   = nPipeForce-2;      //latency of reading data plus ForceNonBond;
localparam           nPipe_ResetFtot = nPipeForce-6;      //timing of ResetFtot and StoreFtot; both signals should come at the same time 
localparam           nPipe_StoreFtot = nPipeForce+2;      //at the end of the 2-cycle addForce break. 

reg                               initHome     = 1'b0;
reg [2*nBox*8-1:0]                nAtom        = 1'b0;
reg                               iHalf; 
reg                               nAtomReset = 1'b0;
reg         [7:0]                 MDadr_000 =1'b0; 
reg         [8:0]                 adr_000 = 1'b0;
wire        [DataByteWidth*8-1:0] dataHome;
reg         [3:0]                 CalcState1 = 1'b0;
reg         [15:0]                istep=1'b1; 
wire                              atomDataReady;
wire                              slowDown,slowDown_x,slowDown_y,slowDown_z,slowDown_xy,slowDown_xz,slowDown_yz,slowDown_xyz;
wire                              forceReady, force_xReady, force_yReady, force_zReady, force_xyReady, force_xzReady, force_yzReady, force_xyzReady;
wire                              overflowSubbox, overflowSubbox_x, overflowSubbox_y, overflowSubbox_z, overflowSubbox_xy, overflowSubbox_xz, overflowSubbox_yz,  overflowSubbox_xyz;
reg                               overflowHomeBox=1'b0,overflowNeighborBox=1'b0;
reg                               HomeReady;
wire                              HomeReady2;
reg         [7:0]                 wait_cnt=1'b0;
reg                               CalcState2_Bussy=1'b0;
reg                               CalcState3_Bussy=1'b0;
reg         [6:0]                 SendMacBox_CalcClk;
                

wire        [DataByteWidth_n*8-1:0] dataBox_00p;
wire        [DataByteWidth_n*8-1:0] dataBox_00n;
wire        [DataByteWidth_n*8-1:0] dataBox_0p0;
wire        [DataByteWidth_n*8-1:0] dataBox_0n0;
wire        [DataByteWidth_n*8-1:0] dataBox_p00;
wire        [DataByteWidth_n*8-1:0] dataBox_n00;
wire        [DataByteWidth_n*8-1:0] dataBox_0pp;
wire        [DataByteWidth_n*8-1:0] dataBox_0pn;
wire        [DataByteWidth_n*8-1:0] dataBox_0np;
wire        [DataByteWidth_n*8-1:0] dataBox_0nn;
wire        [DataByteWidth_n*8-1:0] dataBox_p0p;
wire        [DataByteWidth_n*8-1:0] dataBox_p0n;
wire        [DataByteWidth_n*8-1:0] dataBox_n0p;
wire        [DataByteWidth_n*8-1:0] dataBox_n0n;
wire        [DataByteWidth_n*8-1:0] dataBox_pp0;
wire        [DataByteWidth_n*8-1:0] dataBox_pn0;
wire        [DataByteWidth_n*8-1:0] dataBox_np0;
wire        [DataByteWidth_n*8-1:0] dataBox_nn0;
wire        [DataByteWidth_n*8-1:0] dataBox_ppp;
wire        [DataByteWidth_n*8-1:0] dataBox_ppn;
wire        [DataByteWidth_n*8-1:0] dataBox_pnp;
wire        [DataByteWidth_n*8-1:0] dataBox_pnn;
wire        [DataByteWidth_n*8-1:0] dataBox_npp;
wire        [DataByteWidth_n*8-1:0] dataBox_npn;
wire        [DataByteWidth_n*8-1:0] dataBox_nnp;
wire        [DataByteWidth_n*8-1:0] dataBox_nnn;
 
//****************************accumulating nAtom******************************************** 
integer i;
always @(posedge IOclk) begin
  if(nAtomResetExt||nAtomReset)  begin 
    nAtom[iHalf*nBox*8+:nBox*8]        <= 1'b0;
    overflowHomeBox                    <= 1'b0;
    overflowNeighborBox                <= 1'b0;
  end  
  else begin
    if(data_valid[0]) begin
      nAtom[(iHalf*nBox)*8+:8]  <= nAtom[(iHalf*nBox)*8+:8] + 1'b1;
      if(nAtom[(iHalf*nBox)*8+:8]==8'd252) overflowHomeBox <= 1'b1;       //smaller than 255 since that would cause  overflows in mac.v
    end  
    for(i=1;i<nBox;i=i+1) begin 
      if(data_valid[i]) begin 
        nAtom[(iHalf*nBox+i)*8+:8]  <= nAtom[(iHalf*nBox+i)*8+:8] + 1'b1; 
        if(nAtom[(iHalf*nBox+i)*8+:8]==8'd252) overflowNeighborBox <= 1'b1;
      end    
    end  
  end  
end  
assign nAtom0 = nAtom[nBox*8-1:0];   //for output via mac.v



ClkTransferStat #(.Width (1))  ClkTransferStat1  
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (iHalf),
    .sigOut  (iHalf_CalcClk)
); 



 
ClkTransferStat #(.Width (1))  ClkTransferStat3  
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (CalcBussy),
    .sigOut  (CalcBussy_CalcClk)
); 

wire [7:0] nAtom_iH0;
ClkTransferStat #(.Width (8))  ClkTransferStat4  
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (nAtom[0+:8]),
    .sigOut  (nAtom_iH0)
); 

wire [7:0] nAtom_iH1;
ClkTransferStat #(.Width (8))  ClkTransferStat5  
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (nAtom[8*nBox+:8]),
    .sigOut  (nAtom_iH1)
); 


//memory containing home box (full width), simple-dual, toal latency 3 (including that of the initial adress multiplexer, full width
always @(posedge CalcClk) begin
   adr_000 <= CalcBussy_CalcClk ? {~iHalf_CalcClk,MDadr_000} : {SendMacBox_CalcClk[0],SendMacAdr};
end   
bram_216x512_simple_dual homebox (.clka(IOclk),.ena(1'b1),.wea(data_valid[0]) ,.addra({iHalf,nAtom[(iHalf*nBox+0 )*8 +:8]}),.dina(DataHome),  .clkb(CalcClk),.enb(1'b1),.addrb(adr_000),.doutb(dataHome));


//***************************************actual MD loop*************************************************
always @(posedge IOclk) begin
  if(MDReset) begin
    CalcState1 <= 1'b0;
  end else begin  
    case (CalcState1)
      0: begin                         //idle
       CalcBussy      <= 1'b0;
       nAtomReset     <= 1'b0;
       iHalf          <= 1'b0;
       istep          <= 1'b1;
       errorRxReset   <= 1'b0;
       initHome       <= 1'b0;
       wait_cnt       <= 6'h0;
       if(InitCalc) begin               //initiate calculation
         SyncOut      <= 1'b0;
         CalcState1   <= 4'd1;
       end else SyncOut   <= 1'b1;   
      end     
      1: begin
        istepOut       <= 1'b1;           //for istepOut, remains at the final istep when finished, for statusline    
        CalcBussy      <= 1'b1;   
        if(~AllBussy) begin              //wait until all nodes are ready
          SyncOut        <= 1'b1;
          iHalf          <= ~iHalf;
          nAtomReset     <= 1'b1; 
          CalcState1     <= 4'd2;
        end   
      end
      2: begin                       //a few wait cycles for all signals to propagate through
        nAtomReset       <= 1'b0;
        if(wait_cnt==7'h7) begin
          wait_cnt     <= 6'h0;
          CalcState1   <= 4'd3;
        end else wait_cnt  <= wait_cnt +1'b1;
      end
      3: begin
        if((~iHalf ? nAtom[8*nBox+:8] : nAtom[0+:8]) == 1'b0)   CalcState1 <= 4'd6;  //no atoms; jump over claculation
        else begin
          initHome         <= 1'b1;      //initiate calculation of force calculation in home box in statemachine 2, which in turn also 
          CalcState1       <= 4'd4;      //initiates claculations of neigboring boxes
        end  
      end  
      4: begin
        initHome         <= 1'b0;
        if(HomeReady2) CalcState1 <= 4'd5;   //wait until force calculation (state machine 2) is done
      end    
      5: begin
        if(atomDataReady&&(~CalcState2_Bussy)&&(~CalcState3_Bussy)) begin //wait until all pipelines as well as statemachines 2 and 3 are done
          CalcState1 <= 4'd7;   
          EnsembleReady<= 1'b1;
        end  
      end
      6: begin                         //entry point when no atom; extra wait
        if(wait_cnt==7'h7f) begin
          wait_cnt     <= 6'h0;
          CalcState1   <= 4'd7;
        end else wait_cnt  <= wait_cnt +1'b1;
      end  
      7: begin
        EnsembleReady<= 1'b0; 
        if(wait_cnt==6'h3f) begin    //used to be h10
          wait_cnt     <= 6'h0;
          SyncOut      <= 1'b0;
          CalcState1   <= 4'd8;  //wait a little longer until Broadcast_busy takes over busy signal 
        end else wait_cnt  <= wait_cnt +1'b1;
      end
      8: begin         
        if(~AllBussy) CalcState1 <= 4'd10;
      end      
      10: begin                         //check whether there is rx error
        if(errorRxSync) begin     
          istep         <= istep - 1'b1;  //redo timestep if there has been an error
          iHalf         <= ~iHalf; 
          CalcState1    <= 4'd11;
        end else begin
          CalcState1    <= 4'd13;
        end  
      end
      11: begin                        //wait a little for all sync signals;
        if(wait_cnt==8'hff) begin
          errorRxReset  <= 1'b1;
          wait_cnt   <= 6'h0;
          CalcState1 <= 4'd12;
        end else wait_cnt  <= wait_cnt +1'b1;
      end      
      12: begin                         //wait until all nodes reset the rx_error
        errorRxReset  <=1'b0;
        if(~errorRxSync) CalcState1 <= 4'd13;   
      end          
      13: begin              
        if(istep<nstep) begin 
          istep        <= istep + 1'b1;
          istepOut     <= istep + 1'b1;
          iHalf        <= ~iHalf; 
          SyncOut      <= 1'b1;
          nAtomReset   <= 1'b1; 
          CalcState1   <= 4'd2;     //loop to next timestep
        end else begin
          CalcState1   <= 4'd0; 
          iHalf        <= 1'b0;    //done
        end   
      end    
      default: CalcState1 <= 4'd0;
    endcase
  end  
end    

//************************************************************************
//statemachine that does force calculation of homebox, and also initiates neigboring boxes 
reg         [7:0]                 nAtomCalc_m1 = 1'b0;
reg         [7:0]                 nAtomCalc_m2 = 1'b0;
reg         [3:0]                 HomeState  = 1'b0;
reg         [7:0]                 i1         = 1'b0;
reg                               start_i2    = 1'b0;
reg         [7:0]                 i2          = 1'b0;      
reg         [nPipe_AddFtot:0]     addForce     = 1'b0;
reg  signed [23:0]                x1 = 1'b0, y1=1'b0, z1=1'b0;
reg         [71:0]                metaData=1'b0;
reg  signed [23:0]                vx = 1'b0, vy = 1'b0, vz = 1'b0;
reg  signed [23:0]                dx = 1'b0, dy = 1'b0, dz = 1'b0;
reg  signed [23:0]                x2 = 1'b0, y2 = 1'b0, z2 = 1'b0;
reg                               DoNext_i1=1'b0; 
reg         [nPipe_ResetFtot:0]   ResetFtot  =  1'b0;
reg         [nPipe_StoreFtot:0]   StoreFtot  =  1'b0;
reg                               fifoOut = 1'b0;
reg         [1:0]                 wait_cnt2;
reg                               i2Done;

wire initHome2;
ClkTransfer #(.extend (2)) ClkTransfer1
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (initHome),
    .sigOut  (initHome2)
); 

wire MDReset2;
ClkTransfer #(.extend (2)) ClkTransfer2
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (MDReset),
    .sigOut  (MDReset2)
); 




always @(posedge CalcClk) begin
 addForce  <= {addForce[nPipe_AddFtot-1:0],addForce[0]};
 ResetFtot <= {ResetFtot[nPipe_ResetFtot-1:0],ResetFtot[0]}; 
 StoreFtot <= {StoreFtot[nPipe_StoreFtot-1:0],StoreFtot[0]}; 
 if(MDReset2) begin   
   HomeState <= 1'b0;
 end else begin  
   case (HomeState)
     0: begin                         //idle
       i1             <= 1'b0;
       MDadr_000      <= 1'b0;
       HomeReady      <= 1'b0;
       wait_cnt2      <= 1'b0;    
       if(initHome2) begin
         HomeState<=3'd2;
       end    
     end    
     2: begin     //wait cycles to account for latency of memory 
        nAtomCalc_m1  <= ~iHalf_CalcClk ? (nAtom_iH1-1'b1) : (nAtom_iH0-1'b1);
        nAtomCalc_m2  <= ~iHalf_CalcClk ? (nAtom_iH1-8'd2) : (nAtom_iH0-8'd2);
        wait_cnt2     <= wait_cnt2 +1'b1;
        if(wait_cnt2==latHomeBram-1) HomeState <= 4'd3;
      end   
      3: begin
        x1           <= dataHome[24*0 +:24];
        y1           <= dataHome[24*1 +:24];
        z1           <= dataHome[24*2 +:24];
        metaData     <= dataHome[24*3 +:72];
        start_i2     <= 1'b1;   //initiate various pipelines for other boxes and write atomData into FIFO
        MDadr_000    <= 1'b0;
        i2           <= 1'b0;
        wait_cnt2    <= 1'b0;
        HomeState    <= 4'd4; 
      end   
      4: begin 
        start_i2     <= 1'b0;
        MDadr_000    <= MDadr_000 + 1'b1;   //wait for memory latency
        wait_cnt2    <= wait_cnt2 +1'b1;
        if(wait_cnt2==latHomeBram-1) HomeState <= 4'd5;    
      end   
      5: begin                            
        MDadr_000  <= MDadr_000 + 1'b1;
        x2 <= dataHome[24*0 +:24];
        y2 <= dataHome[24*1 +:24];
        z2 <= dataHome[24*2 +:24];
        ResetFtot[0] <= 1'b1;
        HomeState    <= 4'd6;
        i2Done       <= (nAtomCalc_m1==1'b0);  
      end
      6: begin                     //do homebox calculation
        ResetFtot[0]    <= 1'b0;
        dx              <= x2-x1;  //enters into ForceNonBond
        dy              <= y2-y1;
        dz              <= z2-z1;
        MDadr_000       <= MDadr_000 + 1'b1;
        x2              <= dataHome[24*0 +:24];
        y2              <= dataHome[24*1 +:24];
        z2              <= dataHome[24*2 +:24];
        i2              <= i2 + 1'b1;
//        i2Done          <= ((i2 + 1'b1)>=nAtomCalc_m1);
        i2Done          <= (i2==nAtomCalc_m2);
        addForce[0]     <= 1'b1;
        DoNext_i1       <= (i1<nAtomCalc_m1);
        if(i2Done) begin      
          HomeState <= 4'd7;
        end     
      end
      7: begin
        StoreFtot[0]  <= 1'b1;    
        addForce[0]   <= 1'b0;     
        wait_cnt2     <= 1'b0;
        if(DoNext_i1) HomeState <= 4'd8;  
        else          HomeState <= 4'd9; 
      end  
      8: begin
        StoreFtot[0] <= 1'b0;
        if(~slowDown) begin           //wait for the other pipelines if their input FIFO is getting full
          i1          <= i1 + 1'b1;
          MDadr_000   <= i1 + 1'b1; 
          HomeState   <= 4'd2; 
        end
      end
      9: begin     //done
        StoreFtot[0] <= 1'b0;
        HomeReady <= 1'b1;
        HomeState <= 1'b0;
      end
    endcase
  end  
end


ClkTransfer #(.extend (3)) ClkTransfer3
(
    .clkIn   (CalcClk),
    .clkOut  (IOclk),
    .sigIn   (HomeReady),
    .sigOut  (HomeReady2)
); 

//write atom data into FIFO for final calculation of new coordinates and velocities in statemachine 2
wire [DataByteWidth*8-1:0] dataHomeFifo;
FIFO_216x64 atomData (
  .wr_clk(CalcClk),    
  .rd_clk(IOclk),     
  .din(dataHome),      
  .wr_en(start_i2),  
  .rd_en(fifoOut),  
  .dout(dataHomeFifo),    
  .full(),    
  .empty(atomDataReady)  
);

//************************Forces within Home Box**************************************
wire signed [31:0]    Fx_tot, Fy_tot, Fz_tot; 
ForceNonBond 
#(
.ForceLUTWidth   (ForceLUTWidth)
) ForceNonBondHome
(
.IOclk        (IOclk),
.CalcClk      (CalcClk),
.wrForceLUT   (wrForceLUT),    
.dataForceLUT (dataForceLUT),  
.adrForceLUT  (adrForceLUT),   
.selForceLUT  (selForceLUT),    
.ResetFtot    (ResetFtot[nPipe_ResetFtot]),
.pipe         (addForce[nPipe_AddFtot]),   //(pipe[nPipeForce-1]),
.dx           (dx),
.dy           (dy),
.dz           (dz),
.Fx_tot       (Fx_tot),
.Fy_tot       (Fy_tot), 
.Fz_tot       (Fz_tot)
);

//write forces into FIFO for final calculation of new coordinates and velocities in statemachine 2
wire [95:0]  forceFifo;
wire forceHomeReady;
FIFO_96x64 ForceHome (
  .wr_clk(CalcClk),    
  .rd_clk(IOclk),  
  .din({Fz_tot,Fy_tot,Fx_tot}),      
  .wr_en(StoreFtot[nPipe_StoreFtot]),     //next i2 cycle, but then one clock cycle before reset
  .rd_en(fifoOut),  
  .dout(forceFifo),    
  .full(),    
  .empty(forceHomeReady)  
);

//*****************************parallel pipelines working on neigboring boxes**********************************
// /* //Comment out when only home-box forces are to be calculated

//ATTENTION: nomenclature "n" and "p" stands negative and positive relative to home box, respectively. From the 
//perspective of sending data in BroadcastAtom, signs are opposite. Swap nomenclatiure of signs here when writing 
//into BRAM (i.e., compare to assignemnt of data_valid in BroadcastAtom)
//
//Nr  BOX      SIGNAL          DATA SOURCE
//1:  box_00p: data_valid[1],  gtp0_data_recv
//2:  box_00n: data_valid[2],  gtp1_data_recv
//3:  box_0p0: data_valid[3],  gtp2_data_recv
//4:  box_0pp: data_valid[4],  gtp0_data_recv
//5:  box_0pn: data_valid[5],  gtp2_data_recv
//6:  box_0n0: data_valid[6],  gtp3_data_recv
//7:  box_0np: data_valid[7],  gtp3_data_recv
//8:  box_0nn: data_valid[8],  gtp1_data_recv
//9:  box_p00: data_valid[9],  e3_data_recv
//10: box_p0p: data_valid[10], gtp0_data_recv
//11: box_p0n: data_valid[11], gtp1_data_recv
//12: box_pp0: data_valid[12], gtp2_data_recv
//13  box_ppp: data_valid[13], gtp0_data_recv
//14 box_ppn: data_valid[14], gtp2_data_recv
//15 box_pn0: data_valid[15], gtp3_data_recv
//16 box_pnp: data_valid[16], gtp3_data_recv
//17 box_pnn: data_valid[17], gtp1_data_recv
//18 box_n00: data_valid[18], e4_data_recv
//19 box_n0p: data_valid[19], gtp0_data_recv
//20 box_n0n: data_valid[20], gtp1_data_recv
//21 box_np0: data_valid[21], gtp2_data_recv
//22 box_npp: data_valid[22], gtp0_data_recv
//23 box_npn: data_valid[23], gtp2_data_recv
//24 box_nn0: data_valid[24], gtp3_data_recv
//25 box_nnp: data_valid[25], gtp3_data_recv
//26 box_nnn: data_valid[26], gtp1_data_recv


//neighboring boxes in +/- x-direction, i.e. boxes 00p and 00n
wire        [95:0]    force_xFifo;
ForceBox1 
#(  
.DataByteWidth_n (DataByteWidth_n),
.nPipeForce      (nPipeForce),
.ForceLUTWidth   (ForceLUTWidth),
.q0              (0),
.q1              (1),
.q2              (2)
) ForceBox_x
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write force LUT
.wrForceLUT     (wrForceLUT),    
.dataForceLUT   (dataForceLUT),  
.adrForceLUT    (adrForceLUT),   
.selForceLUT    (selForceLUT),    
//write into BRAM
.data_valid_p   (data_valid[1]),
.data_valid_n   (data_valid[2]),
.iHalf          (iHalf),
.nAtom_p        (nAtom[(iHalf*nBox+1 )*8 +:8]),
.nAtom_n        (nAtom[(iHalf*nBox+2 )*8 +:8]),
.data_p         (gtp0_data_recv),
.data_n         (gtp1_data_recv),
.nAtomReset     (nAtomResetExt||nAtomReset),
.overflowSubbox (overflowSubbox_x),                    
//Calculation pipeline
.iHalf_CalcClk  (iHalf_CalcClk),                               //iHalf on CalcClk for reading
.start_i2       (start_i2),
.dataHome       ({metaData,z1,y1,x1}),
.forceReady     (force_xReady),
.fifoOut        (fifoOut),
.forceFifo      (force_xFifo),
.slowDown       (slowDown_x),
//read Data for MAC/host compuer
.dataBox_p      (dataBox_00p),                               //outout data, contains positions and meta-data
.dataBox_n      (dataBox_00n),                               //outout data, contains positions and meta-data
.CalcBussy      (CalcBussy_CalcClk),                         //CalcBussy, on CalcClk
.SendMacHalf    (SendMacBox_CalcClk[0]),                               //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);

//neighboring boxes in +/- y-direction, i.e. boxes 0p0 and 0n0
wire        [95:0]    force_yFifo;
ForceBox1 
#(  
.DataByteWidth_n (DataByteWidth_n),
.nPipeForce      (nPipeForce),
.ForceLUTWidth   (ForceLUTWidth),
.q0              (1),     //swap x and y 
.q1              (0),
.q2              (2)
) ForceBox_y
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write force LUT
.wrForceLUT     (wrForceLUT),    
.dataForceLUT   (dataForceLUT),  
.adrForceLUT    (adrForceLUT),   
.selForceLUT    (selForceLUT),    
//write into BRAM
.data_valid_p   (data_valid[3]),
.data_valid_n   (data_valid[6]),
.iHalf          (iHalf),                            
.nAtom_p        (nAtom[(iHalf*nBox+3 )*8 +:8]),    
.nAtom_n        (nAtom[(iHalf*nBox+6 )*8 +:8]),     
.data_p         (gtp2_data_recv),
.data_n         (gtp3_data_recv),
.nAtomReset     (nAtomResetExt||nAtomReset),
.overflowSubbox (overflowSubbox_y),
//Calculation pipeline
.iHalf_CalcClk  (iHalf_CalcClk),                               //iHalf on CalcClk for reading
.start_i2       (start_i2),
.dataHome       ({metaData,z1,y1,x1}),                      
.forceReady     (force_yReady),
.fifoOut        (fifoOut),
.forceFifo      (force_yFifo),
.slowDown       (slowDown_y),
//read Data for MAC/host compuer
.dataBox_p      (dataBox_0p0),                               //outout data, contains positions and meta-data
.dataBox_n      (dataBox_0n0),                               //outout data, contains positions and meta-data
.CalcBussy      (CalcBussy_CalcClk),                                 //CalcBussy, on CalcClk
.SendMacHalf    (SendMacBox_CalcClk[0]),                     //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);

//neighboring boxes in +/- z-direction i.e. boxes p00 and n00
wire        [95:0]    force_zFifo;
ForceBox1 
#(  
.DataByteWidth_n (DataByteWidth_n),
.nPipeForce      (nPipeForce),
.ForceLUTWidth   (ForceLUTWidth),
.q0              (2),     //swap x and z 
.q1              (1),
.q2              (0)
) ForceBox_z
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write force LUT
.wrForceLUT     (wrForceLUT),    
.dataForceLUT   (dataForceLUT),  
.adrForceLUT    (adrForceLUT),   
.selForceLUT    (selForceLUT),    
//write into BRAM
.data_valid_p   (data_valid[9]),
.data_valid_n   (data_valid[18]),
.iHalf          (iHalf),
.nAtom_p        (nAtom[(iHalf*nBox+9 )*8 +:8]),
.nAtom_n        (nAtom[(iHalf*nBox+18)*8 +:8]),
.data_p         (e3_data_recv),
.data_n         (e4_data_recv),
.nAtomReset     (nAtomResetExt||nAtomReset),
.overflowSubbox (overflowSubbox_z),
//Calculation pipeline
.iHalf_CalcClk  (iHalf_CalcClk),                               //iHalf on CalcClk for reading
.start_i2       (start_i2),
.dataHome       ({metaData,z1,y1,x1}),
.forceReady     (force_zReady),
.fifoOut        (fifoOut),
.forceFifo      (force_zFifo),
.slowDown       (slowDown_z),
//read Data for MAC/host compuer
.dataBox_p      (dataBox_p00),                               //outout data, contains positions and meta-data
.dataBox_n      (dataBox_n00),                               //outout data, contains positions and meta-data
.CalcBussy      (CalcBussy_CalcClk),                                 //CalcBussy, on CalcClk
.SendMacHalf    (SendMacBox_CalcClk[0]),                     //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);


//neighboring boxes in the (xy)-corners, i.e. boxes 0pp, 0pn, 0np, 0nn
wire        [95:0]    force_xyFifo;
ForceBox12 
#(  
.DataByteWidth_n (DataByteWidth_n),
.nPipeForce      (nPipeForce),
.ForceLUTWidth   (ForceLUTWidth),
.q0              (0),     
.q1              (1),
.q2              (2)
) ForceBox_xy
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write force LUT
.wrForceLUT     (wrForceLUT),    
.dataForceLUT   (dataForceLUT),  
.adrForceLUT    (adrForceLUT),   
.selForceLUT    (selForceLUT),    
//write into BRAM
.data_valid_pp  (data_valid[4]),
.data_valid_pn  (data_valid[5]),
.data_valid_np  (data_valid[7]),
.data_valid_nn  (data_valid[8]),
.iHalf          (iHalf),
.nAtom_pp       (nAtom[(iHalf*nBox+4 )*8 +:8]),
.nAtom_pn       (nAtom[(iHalf*nBox+5 )*8 +:8]),
.nAtom_np       (nAtom[(iHalf*nBox+7 )*8 +:8]),
.nAtom_nn       (nAtom[(iHalf*nBox+8 )*8 +:8]),
.data_pp        (gtp0_data_recv),
.data_pn        (gtp2_data_recv),
.data_np        (gtp3_data_recv),
.data_nn        (gtp1_data_recv),
.nAtomReset     (nAtomResetExt||nAtomReset),
.overflowSubbox (overflowSubbox_xy), 
//Calculation pipeline
.iHalf_CalcClk  (iHalf_CalcClk),                               //iHalf on CalcClk for reading
.start_i2       (start_i2),
.dataHome       ({metaData,z1,y1,x1}),
.forceReady     (force_xyReady),
.fifoOut        (fifoOut),
.forceFifo      (force_xyFifo),
.slowDown       (slowDown_xy),
//read Data for MAC/host compuer
.dataBox_pp     (dataBox_0pp),                               //outout data, contains positions and meta-data
.dataBox_pn     (dataBox_0pn),                               //outout data, contains positions and meta-data
.dataBox_np     (dataBox_0np),                               //outout data, contains positions and meta-data
.dataBox_nn     (dataBox_0nn),                               //outout data, contains positions and meta-data
.CalcBussy      (CalcBussy_CalcClk),                                 //CalcBussy, on CalcClk
.SendMacHalf    (SendMacBox_CalcClk[0]),                     //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);


//neighboring boxes in the (xz)-corners, i.e. boxes p0p, p0n, n0p, n0n
wire        [95:0]    force_xzFifo;
ForceBox12 
#(  
.DataByteWidth_n (DataByteWidth_n),
.nPipeForce      (nPipeForce),
.ForceLUTWidth   (ForceLUTWidth),
.q0              (0),     //swap y and z 
.q1              (2),
.q2              (1)
) ForceBox_xz
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write force LUT
.wrForceLUT     (wrForceLUT),    
.dataForceLUT   (dataForceLUT),  
.adrForceLUT    (adrForceLUT),   
.selForceLUT    (selForceLUT),    
//write into BRAM
.data_valid_pp  (data_valid[10]),
.data_valid_pn  (data_valid[11]),
.data_valid_np  (data_valid[19]),
.data_valid_nn  (data_valid[20]),
.iHalf          (iHalf),
.nAtom_pp       (nAtom[(iHalf*nBox+10)*8 +:8]),
.nAtom_pn       (nAtom[(iHalf*nBox+11)*8 +:8]),
.nAtom_np       (nAtom[(iHalf*nBox+19)*8 +:8]),
.nAtom_nn       (nAtom[(iHalf*nBox+20)*8 +:8]),
.data_pp        (gtp0_data_recv),
.data_pn        (gtp1_data_recv),
.data_np        (gtp0_data_recv),
.data_nn        (gtp1_data_recv),
.nAtomReset     (nAtomResetExt||nAtomReset),
.overflowSubbox (overflowSubbox_xz),
//Calculation pipeline
.iHalf_CalcClk  (iHalf_CalcClk),                               //iHalf on CalcClk for reading
.start_i2       (start_i2),
.dataHome       ({metaData,z1,y1,x1}),
.forceReady     (force_xzReady),
.fifoOut        (fifoOut),
.forceFifo      (force_xzFifo),
.slowDown       (slowDown_xz),
//read Data for MAC/host compuer
.dataBox_pp     (dataBox_p0p),                               //outout data, contains positions and meta-data
.dataBox_pn     (dataBox_p0n),                               //outout data, contains positions and meta-data
.dataBox_np     (dataBox_n0p),                               //outout data, contains positions and meta-data
.dataBox_nn     (dataBox_n0n),                               //outout data, contains positions and meta-data
.CalcBussy      (CalcBussy_CalcClk),                                 //CalcBussy, on CalcClk
.SendMacHalf    (SendMacBox_CalcClk[0]),                     //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);

//neighboring boxes in the (yz)-corners, i.e. boxes pp0, pn0, np0, nn0
wire        [95:0]    force_yzFifo;
ForceBox12 
#(  
.DataByteWidth_n (DataByteWidth_n),
.nPipeForce      (nPipeForce),
.ForceLUTWidth   (ForceLUTWidth),
.q0              (2),     //swap x and z 
.q1              (1),
.q2              (0)
) ForceBox_yz
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write force LUT
.wrForceLUT     (wrForceLUT),    
.dataForceLUT   (dataForceLUT),  
.adrForceLUT    (adrForceLUT),   
.selForceLUT    (selForceLUT),    
//write into BRAM
.data_valid_pp  (data_valid[12]),
.data_valid_pn  (data_valid[21]),                    //pn and np swapped due to xz swapping
.data_valid_np  (data_valid[15]),
.data_valid_nn  (data_valid[24]),
.iHalf          (iHalf),
.nAtom_pp       (nAtom[(iHalf*nBox+12)*8 +:8]),
.nAtom_pn       (nAtom[(iHalf*nBox+21)*8 +:8]),     //pn and np swapped due to xz swapping
.nAtom_np       (nAtom[(iHalf*nBox+15)*8 +:8]),
.nAtom_nn       (nAtom[(iHalf*nBox+24)*8 +:8]),
.data_pp        (gtp2_data_recv),
.data_pn        (gtp2_data_recv),                  //pn and np swapped due to xz swapping
.data_np        (gtp3_data_recv),
.data_nn        (gtp3_data_recv),
.nAtomReset     (nAtomResetExt||nAtomReset),
.overflowSubbox (overflowSubbox_yz),
//Calculation pipeline
.iHalf_CalcClk  (iHalf_CalcClk),                               //iHalf on CalcClk for reading
.start_i2       (start_i2),
.dataHome       ({metaData,z1,y1,x1}),
.forceReady     (force_yzReady),
.fifoOut        (fifoOut),
.forceFifo      (force_yzFifo),
.slowDown       (slowDown_yz),
//read Data for MAC/host compuer
.dataBox_pp     (dataBox_pp0),                               //outout data, contains positions and meta-data
.dataBox_pn     (dataBox_np0),                               //outout data, pn and np swapped due to xz swapping
.dataBox_np     (dataBox_pn0),                               //outout data, pn and np swapped due to xz swapping
.dataBox_nn     (dataBox_nn0),                               //outout data, contains positions and meta-data
.CalcBussy      (CalcBussy_CalcClk),                         //CalcBussy, on CalcClk
.SendMacHalf    (SendMacBox_CalcClk[0]),                     //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);

//neighboring boxes in the (xyz)-corners, i.e. boxes ppp, ppn, pnp, pnn, npp, npn, nnp, nnn
wire        [95:0]    force_xyzFifo;
ForceBox123
#(  
.DataByteWidth_n (DataByteWidth_n),
.nPipeForce      (nPipeForce),
.ForceLUTWidth   (ForceLUTWidth)
) ForceBox_xyz
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write force LUT
.wrForceLUT     (wrForceLUT),    
.dataForceLUT   (dataForceLUT),  
.adrForceLUT    (adrForceLUT),   
.selForceLUT    (selForceLUT),    
//write into BRAM
.data_valid_ppp (data_valid[13]),
.data_valid_ppn (data_valid[14]),
.data_valid_pnp (data_valid[16]),
.data_valid_pnn (data_valid[17]),
.data_valid_npp (data_valid[22]),
.data_valid_npn (data_valid[23]),
.data_valid_nnp (data_valid[25]),
.data_valid_nnn (data_valid[26]),
.iHalf          (iHalf),
.nAtom_ppp      (nAtom[(iHalf*nBox+13)*8 +:8]),
.nAtom_ppn      (nAtom[(iHalf*nBox+14)*8 +:8]),
.nAtom_pnp      (nAtom[(iHalf*nBox+16)*8 +:8]),
.nAtom_pnn      (nAtom[(iHalf*nBox+17)*8 +:8]),
.nAtom_npp      (nAtom[(iHalf*nBox+22)*8 +:8]),
.nAtom_npn      (nAtom[(iHalf*nBox+23)*8 +:8]),
.nAtom_nnp      (nAtom[(iHalf*nBox+25)*8 +:8]),
.nAtom_nnn      (nAtom[(iHalf*nBox+26)*8 +:8]),
.data_ppp       (gtp0_data_recv),
.data_ppn       (gtp2_data_recv),
.data_pnp       (gtp3_data_recv),
.data_pnn       (gtp1_data_recv),
.data_npp       (gtp0_data_recv),
.data_npn       (gtp2_data_recv),
.data_nnp       (gtp3_data_recv),
.data_nnn       (gtp1_data_recv),
.nAtomReset     (nAtomResetExt||nAtomReset),
.overflowSubbox (overflowSubbox_xyz),
//Calculation pipeline
.iHalf_CalcClk  (iHalf_CalcClk),                               //iHalf on CalcClk for reading
.start_i2       (start_i2),
.dataHome       ({metaData,z1,y1,x1}),
.forceReady     (force_xyzReady),
.fifoOut        (fifoOut),
.forceFifo      (force_xyzFifo),
.slowDown       (slowDown_xyz),
//read Data for MAC/host compuer
.dataBox_ppp    (dataBox_ppp),                               //outout data, contains positions and meta-data
.dataBox_ppn    (dataBox_ppn),                               //outout data, contains positions and meta-data
.dataBox_pnp    (dataBox_pnp),                               //outout data, contains positions and meta-data
.dataBox_pnn    (dataBox_pnn),                               //outout data, contains positions and meta-data
.dataBox_npp    (dataBox_npp),                               //outout data, contains positions and meta-data
.dataBox_npn    (dataBox_npn),                               //outout data, contains positions and meta-data
.dataBox_nnp    (dataBox_nnp),                               //outout data, contains positions and meta-data
.dataBox_nnn    (dataBox_nnn),                               //outout data, contains positions and meta-data
.CalcBussy      (CalcBussy_CalcClk),                                 //CalcBussy, on CalcClk
.SendMacHalf    (SendMacBox_CalcClk[0]),                     //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  


);

wire signed [31:0]      Fx_x_Fifo   = force_xFifo[32*0 +:32]; 
wire signed [31:0]      Fy_x_Fifo   = force_xFifo[32*1 +:32];  
wire signed [31:0]      Fz_x_Fifo   = force_xFifo[32*2 +:32]; 
wire signed [31:0]      Fx_y_Fifo   = force_yFifo[32*0 +:32]; 
wire signed [31:0]      Fy_y_Fifo   = force_yFifo[32*1 +:32];  
wire signed [31:0]      Fz_y_Fifo   = force_yFifo[32*2 +:32]; 
wire signed [31:0]      Fx_z_Fifo   = force_zFifo[32*0 +:32]; 
wire signed [31:0]      Fy_z_Fifo   = force_zFifo[32*1 +:32];  
wire signed [31:0]      Fz_z_Fifo   = force_zFifo[32*2 +:32]; 
wire signed [31:0]      Fx_xy_Fifo  = force_xyFifo[32*0 +:32]; 
wire signed [31:0]      Fy_xy_Fifo  = force_xyFifo[32*1 +:32];  
wire signed [31:0]      Fz_xy_Fifo  = force_xyFifo[32*2 +:32]; 
wire signed [31:0]      Fx_xz_Fifo  = force_xzFifo[32*0 +:32]; 
wire signed [31:0]      Fy_xz_Fifo  = force_xzFifo[32*1 +:32];  
wire signed [31:0]      Fz_xz_Fifo  = force_xzFifo[32*2 +:32];
wire signed [31:0]      Fx_yz_Fifo  = force_yzFifo[32*0 +:32]; 
wire signed [31:0]      Fy_yz_Fifo  = force_yzFifo[32*1 +:32];  
wire signed [31:0]      Fz_yz_Fifo  = force_yzFifo[32*2 +:32];
wire signed [31:0]      Fx_xyz_Fifo = force_xyzFifo[32*0 +:32]; 
wire signed [31:0]      Fy_xyz_Fifo = force_xyzFifo[32*1 +:32];  
wire signed [31:0]      Fz_xyz_Fifo = force_xyzFifo[32*2 +:32];

// */ //Comment out when only home box forces are to be calculated
//****************************************************************************************************************************
//statemachine 2 that collects results from various pipelines, and performs final calculation of new positions and velocities
reg         [3:0]       CalcState2  = 1'b0;
wire signed [23:0]      x1_d0       = dataHomeFifo[24*0 +:24]; 
wire signed [23:0]      y1_d0       = dataHomeFifo[24*1 +:24]; 
wire signed [23:0]      z1_d0       = dataHomeFifo[24*2 +:24];
wire        [71:0]      metaData_d0 = dataHomeFifo[24*3 +:72];
wire signed [23:0]      vx_d0       = dataHomeFifo[24*6 +:24];
wire signed [23:0]      vy_d0       = dataHomeFifo[24*7 +:24];
wire signed [23:0]      vz_d0       = dataHomeFifo[24*8 +:24];
wire signed [31:0]      Fx_Fifo     = forceFifo[32*0 +:32]; 
wire signed [31:0]      Fy_Fifo     = forceFifo[32*1 +:32]; 
wire signed [31:0]      Fz_Fifo     = forceFifo[32*2 +:32]; 

reg  signed [31:0]      Fx_1=1'b0, Fx_2=1'b0, Fx_3=1'b0, Fx_4=1'b0; 
reg  signed [31:0]      Fy_1=1'b0, Fy_2=1'b0, Fy_3=1'b0, Fy_4=1'b0; 
reg  signed [31:0]      Fz_1=1'b0, Fz_2=1'b0, Fz_3=1'b0, Fz_4=1'b0; 
reg  signed [23:0]      vx_d3  = 1'b0,  vy_d3 = 1'b0, vz_d3 = 1'b0;
reg  signed [31:0]      Fx_all = 1'b0, Fy_all = 1'b0, Fz_all = 1'b0;
reg  signed [23:0]      Fx_rnd = 1'b0, Fy_rnd = 1'b0, Fz_rnd = 1'b0;

wire [47:0] T_ratio;
//reg  [23:0] T_target=24'h1948B1;   //is the inverse of 24'h0a2000
reg  [16:0] T_scale;
reg         T_scaleOn_d0    = 1'b0;
reg         vcm_shiftOn_d0  = 1'b0;

reg         [47:0]                Temp=1'b0;
reg         [27:0]                TempAll_d0=1'b0;
reg         [27:0]                TempAll=1'b0;
reg  signed [31:0]                vxcm=1'b0;
reg  signed [31:0]                vycm=1'b0;
reg  signed [31:0]                vzcm=1'b0;
reg  signed [23:0]                vxcmAll=1'b0;
reg  signed [23:0]                vycmAll=1'b0;
reg  signed [23:0]                vzcmAll=1'b0;
reg  signed [23:0]                vxcmAll_d0=1'b0;
reg  signed [23:0]                vycmAll_d0=1'b0;
reg  signed [23:0]                vzcmAll_d0=1'b0;
 
//Comment out when only home box forces are to be calculated 
  assign forceReady = (~forceHomeReady)&&(~force_xReady)&&(~force_yReady)&&(~force_xyReady)&&(~force_zReady)&&(~force_xzReady)&&(~force_yzReady)&&(~force_xyzReady);
  assign overflowSubbox = overflowSubbox_x||overflowSubbox_y||overflowSubbox_xy||overflowSubbox_z||overflowSubbox_xz||overflowSubbox_yz||overflowSubbox_xyz;
  assign overflowError = {overflowSubbox,overflowNeighborBox,overflowHomeBox};
  assign slowDown=slowDown_x||slowDown_y||slowDown_xy||slowDown_z||slowDown_xz||slowDown_yz||slowDown_xyz;

//Comment out when all forces are to be calculated 
//  assign forceReady = (~forceHomeReady);
//  assign slowDown = 1'b0;
//  assign overflowError = {1'b0,overflowNeighborBox,overflowHomeBox};

//scale velocities for themostat and shift center-of-mass
wire signed [40:0]      vx_d1,  vy_d1, vz_d1;
wire signed [23:0]  vxcmAll_tmp=-(vxcmAll>>>6);  //devide by additional 2^6, which accounts for the 27 nodes (about 5 bit), plus a bit of a time constant
wire signed [23:0]  vycmAll_tmp=-(vycmAll>>>6);
wire signed [23:0]  vzcmAll_tmp=-(vzcmAll>>>6);
mult_s24xu17    mult_scale_vx (.CLK(IOclk),.A(vx_d0),.B((T_scaleOn_d0 && T_scaleOn) ? T_scale : 17'h10000),.P(vx_d1));
mult_s24xu17    mult_scale_vy (.CLK(IOclk),.A(vy_d0),.B((T_scaleOn_d0 && T_scaleOn) ? T_scale : 17'h10000),.P(vy_d1));
mult_s24xu17    mult_scale_vz (.CLK(IOclk),.A(vz_d0),.B((T_scaleOn_d0 && T_scaleOn) ? T_scale : 17'h10000),.P(vz_d1));
wire signed [23:0] vx_d2 = vx_d1[39:16] + Fx_rnd + ((vcm_shiftOn && vcm_shiftOn_d0) ? vxcmAll_tmp : 24'h000000);   
wire signed [23:0] vy_d2 = vy_d1[39:16] + Fy_rnd + ((vcm_shiftOn && vcm_shiftOn_d0) ? vycmAll_tmp : 24'h000000);
wire signed [23:0] vz_d2 = vz_d1[39:16] + Fz_rnd + ((vcm_shiftOn && vcm_shiftOn_d0) ? vzcmAll_tmp : 24'h000000);


always @(posedge IOclk) begin  //run on IOclk to minimize resources that run at full speed. Is not really pipelined, so full speed is not relevant here
  case (CalcState2)
    0: begin
      newDataReady   <= 1'b0;   
      if(forceReady) begin 
        CalcState2_Bussy <= 1'b1;
        fifoOut          <= 1'b1;
        CalcState2       <= 4'd1; 
      end  
    end
    1: begin
      fifoOut    <= 1'b0;
      CalcState2 <= 4'd2;  //wait for FIFO latency
    end
    2: begin
// /* //Comment out when only home box forces are to be calculated           
      Fx_1 <= Fx_Fifo    + Fx_x_Fifo;     //add up forces from various pipelines 
      Fx_2 <= Fx_y_Fifo  + Fx_z_Fifo;
      Fx_3 <= Fx_xy_Fifo + Fx_xz_Fifo; 
      Fx_4 <= Fx_yz_Fifo + Fx_xyz_Fifo;  
      Fy_1 <= Fy_Fifo    + Fy_x_Fifo; 
      Fy_2 <= Fy_y_Fifo  + Fy_z_Fifo;
      Fy_3 <= Fy_xy_Fifo + Fy_xz_Fifo;
      Fy_4 <= Fy_yz_Fifo + Fy_xyz_Fifo;
      Fz_1 <= Fz_Fifo    + Fz_x_Fifo; 
      Fz_2 <= Fz_y_Fifo  + Fz_z_Fifo; 
      Fz_3 <= Fz_xy_Fifo + Fz_xz_Fifo; 
      Fz_4 <= Fz_yz_Fifo + Fz_xyz_Fifo;
// */ //Comment out when only home box forces are to be calculated
      CalcState2 <= 4'd3;   
    end
    3: begin
//Comment out when only home box forces are to be calculated       
      Fx_all <= Fx_1 + Fx_2 + Fx_3 + Fx_4;
      Fy_all <= Fy_1 + Fy_2 + Fy_3 + Fy_4;
      Fz_all <= Fz_1 + Fz_2 + Fz_3 + Fz_4;
//Comment out when all forces are to be calculated      
//      Fx_all <= Fx_Fifo;       
//      Fy_all <= Fy_Fifo; 
//      Fz_all <= Fz_Fifo;      
      
      CalcState2 <= 4'd4; 
    end
    4: begin  
      Fx_rnd <= Fx_all[31:8] + Fx_all[7]; //round
      Fy_rnd <= Fy_all[31:8] + Fy_all[7];
      Fz_rnd <= Fz_all[31:8] + Fz_all[7];
      CalcState2 <= 4'd5; 
    end
    5: begin   //wait for latency 3 of multiplier
      //assign vx_d2 = T_scale* vx_d0 + Fx_rnd - (vxcmAll>>>5);;  //done above
      //assign vy_d2 = T_scale* vy_d0 + Fy_rnd - (vycmAll>>>5);;
      //assign vz_d2 = T_scale* vz_d0 + Fz_rnd - (vzcmAll>>>5);;    
      CalcState2 <= 4'd6; 
    end
    6: begin
  //check for overflows    
      vx_d3  <= (vx_d1[39]==1'b1)&&(Fx_rnd[23]==1'b1)&&(vx_d2[23]==1'b0) ? 24'h800000 :        //negative overflow, set to largest neg. number
                (vx_d1[39]==1'b0)&&(Fx_rnd[23]==1'b0)&&(vx_d2[23]==1'b1) ? 24'h7fffff :        //positive overflow, set to largest pos. number
                                                                                        vx_d2;        
      vy_d3  <= (vy_d1[39]==1'b1)&&(Fy_rnd[23]==1'b1)&&(vy_d2[23]==1'b0) ? 24'h800000 :        //negative overflow, set to largest neg. number
                (vy_d1[39]==1'b0)&&(Fy_rnd[23]==1'b0)&&(vy_d2[23]==1'b1) ? 24'h7fffff :        //positive overflow, set to largest pos. number
                                                                                        vy_d2;        
      vz_d3  <= (vz_d1[39]==1'b1)&&(Fz_rnd[23]==1'b1)&&(vz_d2[23]==1'b0) ? 24'h800000 :        //negative overflow, set to largest neg. number
                (vz_d1[39]==1'b0)&&(Fz_rnd[23]==1'b0)&&(vz_d2[23]==1'b1) ? 24'h7fffff :        //positive overflow, set to largest pos. number
                                                                                        vz_d2;
      CalcState2    <= 4'd7;
    end
    7: begin
//add (z,y,x)+(vz,vy,vx)>>v_shift + round-off    
      newData          <= {vz_d3,vy_d3,vx_d3,metaData_d0,(z1_d0+{{v_shift{vz_d3[23]}},vz_d3[23:v_shift]}+vz_d3[v_shift-1]),(y1_d0+{{v_shift{vy_d3[23]}},vy_d3[23:v_shift]}+vy_d3[v_shift-1]),(x1_d0+{{v_shift{vx_d3[23]}},vx_d3[23:v_shift]}+vx_d3[v_shift-1])};
      newDataReady     <= 1'b1;       //initiate broadcast of the newly claculated data
      CalcState2       <= 4'd8;
    end
    8: begin
      newDataReady     <= 1'b0;
      CalcState2_Bussy <= 1'b0;
      CalcState2       <= 4'd0;
    end
    default: CalcState2 <= 4'd0;
  endcase      
end

//**********************************************calculate ensemble data**********************************
reg  [3:0]  CalcState3=1'b0;
wire [47:0] vx2,vy2,vz2;



mult24x24    mult_vx2 (.CLK(IOclk),.A(vx_d3),.B(vx_d3),.P(vx2));
mult24x24    mult_vy2 (.CLK(IOclk),.A(vy_d3),.B(vy_d3),.P(vy2));
mult24x24    mult_vz2 (.CLK(IOclk),.A(vz_d3),.B(vz_d3),.P(vz2));

mult_u24xu24 mult_Tratio (.CLK(IOclk),.A(TempAll[27:4]),.B(T_target),.P(T_ratio));

wire signed [16:0] T_ratio_tmp = T_ratio[40:24]-17'h10000; 
wire signed [16:0] T_ratio_tmp2 = -(T_ratio_tmp>>>(4'd1+T_scaleTau)); 

always @(posedge IOclk) begin
  if(MDReset) begin
    T_scaleOn_d0   <= 1'b0;
    vcm_shiftOn_d0 <= 1'b0;
  end
  else if(EnsembleReady) begin
    T_scaleOn_d0   <= T_scaleOn;        //switch on velocity scaling at next step
    vcm_shiftOn_d0 <= vcm_shiftOn;
  end  
//calcculate scaling factor
  T_scale <= 17'h10000+T_ratio_tmp2;   //calculate s=1/r^(1/n) where r=1+x as 1-x/n
//sum up ensemble data from neigboring nodes
  if(nAtomReset) begin   
    TempAll     <= TempAll_d0+Temp[44:21];
    vxcmAll     <= vxcmAll_d0+vxcm[31:8];
    vycmAll     <= vycmAll_d0+vycm[31:8];
    vzcmAll     <= vzcmAll_d0+vzcm[31:8];
    TempAll_d0  <= 1'b0;
    vxcmAll_d0  <= 1'b0;  
    vycmAll_d0  <= 1'b0;
    vzcmAll_d0  <= 1'b0;
  end else if(EnsembleNeighborValid) begin
    TempAll_d0  <= TempAll_d0 + EnsembleNeighbor[23:0];
    vxcmAll_d0  <= vxcmAll_d0 + EnsembleNeighbor[24+:24];
    vycmAll_d0  <= vycmAll_d0 + EnsembleNeighbor[48+:24];
    vzcmAll_d0  <= vzcmAll_d0 + EnsembleNeighbor[72+:24];
  end    
//sum up local ensemble data   
  case (CalcState3)
    0: begin
      if(nAtomReset) begin
        Temp <= 1'b0;
        vxcm <= 1'b0;
        vycm <= 1'b0;
        vzcm <= 1'b0;
      end  
      if(newDataReady) begin
        CalcState3_Bussy <= 1'b1;
        CalcState3<=3'd1;
      end  
    end
    1,2: begin
      CalcState3 <= CalcState3+1'b1;
    end  
    3: begin
      Temp <= (Temp + vx2) + (vy2 +vz2); 
      vxcm <= vxcm + vx_d3;
      vycm <= vycm + vy_d3;
      vzcm <= vzcm + vz_d3;
      CalcState3 <= 3'd4;
    end
    4: begin
      CalcState3 <= 3'd0;
      CalcState3_Bussy <= 1'b0;
    end
  endcase
end  

assign  EnsembleData={vzcm[31:8],vycm[31:8],vxcm[31:8],Temp[44:21]};   //divide center-of-mass by 2^8, which accounts for the maximum number of particles

//**********************************************sending box data to MAC********************************
//read only homebox. BRAM latency is 3; this register adds 1, which is what MAC is designed for
/*
reg [DataByteWidth*8-1:0]   dataHome_d0;
reg [DataByteWidth*8-1:0]   dataHome_d1;
always @(posedge CalcClk) begin
   dataHome_d0 <= dataHome;
   dataHome_d1 <= dataHome_d0;
   DataSendMac <= dataHome_d1;
end
*/

//hirachical multiplexer to optimize fo speed; adds latency 3  
reg [DataByteWidth*8-1:0]   dataBox_00;
reg [DataByteWidth_n*8-1:0] dataBox_0p,dataBox_0n,dataBox_pp,dataBox_pn,dataBox_np,dataBox_nn; 
reg [DataByteWidth*8-1:0]   dataBox_0;
reg [DataByteWidth_n*8-1:0] dataBox_p,dataBox_n;
reg [DataByteWidth_n*8-1:0] dataBox_p0,dataBox_n0; 



//change 5-bit code for box selection (i.e., 0...26) into binary 6bit code. Lowest bit, which is the half to be read 
//is just wired through. 
reg [6:0] SendMacBox_d0;
always @(posedge IOclk) begin
  case (SendMacBox[5:1])
    5'd0:  SendMacBox_d0<={2'd0,2'd0,2'd0,SendMacBox[0]};
    5'd1:  SendMacBox_d0<={2'd0,2'd0,2'd1,SendMacBox[0]};
    5'd2:  SendMacBox_d0<={2'd0,2'd0,2'd2,SendMacBox[0]};
    5'd3:  SendMacBox_d0<={2'd0,2'd1,2'd0,SendMacBox[0]};
    5'd4:  SendMacBox_d0<={2'd0,2'd1,2'd1,SendMacBox[0]};
    5'd5:  SendMacBox_d0<={2'd0,2'd1,2'd2,SendMacBox[0]};
    5'd6:  SendMacBox_d0<={2'd0,2'd2,2'd0,SendMacBox[0]};
    5'd7:  SendMacBox_d0<={2'd0,2'd2,2'd1,SendMacBox[0]};
    5'd8:  SendMacBox_d0<={2'd0,2'd2,2'd2,SendMacBox[0]};
    
    5'd9:  SendMacBox_d0<={2'd1,2'd0,2'd0,SendMacBox[0]};
    5'd10: SendMacBox_d0<={2'd1,2'd0,2'd1,SendMacBox[0]};
    5'd11: SendMacBox_d0<={2'd1,2'd0,2'd2,SendMacBox[0]};
    5'd12: SendMacBox_d0<={2'd1,2'd1,2'd0,SendMacBox[0]};
    5'd13: SendMacBox_d0<={2'd1,2'd1,2'd1,SendMacBox[0]};
    5'd14: SendMacBox_d0<={2'd1,2'd1,2'd2,SendMacBox[0]};
    5'd15: SendMacBox_d0<={2'd1,2'd2,2'd0,SendMacBox[0]};
    5'd16: SendMacBox_d0<={2'd1,2'd2,2'd1,SendMacBox[0]};
    5'd17: SendMacBox_d0<={2'd1,2'd2,2'd2,SendMacBox[0]};
    
    5'd18: SendMacBox_d0<={2'd2,2'd0,2'd0,SendMacBox[0]};
    5'd19: SendMacBox_d0<={2'd2,2'd0,2'd1,SendMacBox[0]};
    5'd20: SendMacBox_d0<={2'd2,2'd0,2'd2,SendMacBox[0]};
    5'd21: SendMacBox_d0<={2'd2,2'd1,2'd0,SendMacBox[0]};
    5'd22: SendMacBox_d0<={2'd2,2'd1,2'd1,SendMacBox[0]};
    5'd23: SendMacBox_d0<={2'd2,2'd1,2'd2,SendMacBox[0]};
    5'd24: SendMacBox_d0<={2'd2,2'd2,2'd0,SendMacBox[0]};
    5'd25: SendMacBox_d0<={2'd2,2'd2,2'd1,SendMacBox[0]};
    5'd26: SendMacBox_d0<={2'd2,2'd2,2'd2,SendMacBox[0]};            
  endcase
end  


always @(posedge CalcClk) begin       //transfer with set_false_path and set_max_delay 30ns to relax timing; worked at 300MHz but gave warning 
  SendMacBox_CalcClk      <= SendMacBox_d0;
end  

always @(posedge CalcClk) begin
  case (SendMacBox_CalcClk[2:1])
    2'd0: begin
      dataBox_00 <= dataHome;
      dataBox_0p <= dataBox_0p0;
      dataBox_0n <= dataBox_0n0;
      dataBox_p0 <= dataBox_p00;
      dataBox_pp <= dataBox_pp0;
      dataBox_pn <= dataBox_pn0;
      dataBox_n0 <= dataBox_n00;
      dataBox_np <= dataBox_np0;
      dataBox_nn <= dataBox_nn0;
    end
    2'd1: begin
      dataBox_00 <= {{(DataByteWidth-DataByteWidth_n)*8{1'b0}},dataBox_00p};
      dataBox_0p <= dataBox_0pp;
      dataBox_0n <= dataBox_0np;
      dataBox_p0 <= dataBox_p0p;
      dataBox_pp <= dataBox_ppp;
      dataBox_pn <= dataBox_pnp;
      dataBox_n0 <= dataBox_n0p;
      dataBox_np <= dataBox_npp;
      dataBox_nn <= dataBox_nnp;
    end
    2'd2: begin
      dataBox_00 <= {{(DataByteWidth-DataByteWidth_n)*8{1'b0}},dataBox_00n};
      dataBox_0p <= dataBox_0pn;
      dataBox_0n <= dataBox_0nn;
      dataBox_p0 <= dataBox_p0n;
      dataBox_pp <= dataBox_ppn;
      dataBox_pn <= dataBox_pnn;
      dataBox_n0 <= dataBox_n0n;
      dataBox_np <= dataBox_npn;
      dataBox_nn <= dataBox_nnn;
    end
  endcase
  case (SendMacBox_CalcClk[4:3])
    2'd0:  begin
      dataBox_0 <= dataBox_00;
      dataBox_p <= dataBox_p0;
      dataBox_n <= dataBox_n0;
    end
    2'd1: begin
      dataBox_0 <= {{(DataByteWidth-DataByteWidth_n)*8{1'b0}},dataBox_0p};
      dataBox_p <= dataBox_pp;
      dataBox_n <= dataBox_np;
    end
    2'd2: begin
      dataBox_0 <= {{(DataByteWidth-DataByteWidth_n)*8{1'b0}},dataBox_0n};
      dataBox_p <= dataBox_pn;
      dataBox_n <= dataBox_nn;
    end
  endcase  
  case (SendMacBox_CalcClk[6:5])
    2'd0: begin
      DataSendMac <= dataBox_0;
    end
    2'd1: begin
      DataSendMac <= {{(DataByteWidth-DataByteWidth_n)*8{1'b0}},dataBox_p};
    end
    2'd2: begin
      DataSendMac <= {{(DataByteWidth-DataByteWidth_n)*8{1'b0}},dataBox_n};
    end
  endcase  
end

   

endmodule
