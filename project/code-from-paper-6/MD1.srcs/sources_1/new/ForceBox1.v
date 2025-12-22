`timescale 1ns / 1ps

//-pipeline for calculation of the non-bonded forces with atoms in neigboring boxes in plus/minus x-direction. 
//-With the parameters (q0,q1,q2), it can be re-programmed to also do y- and z-directions. 
//-overall structure and timing of ForceBox1, ForceBox12 and ForceBox123 the same
//-FIFO-buffered at the input (i.e., coordinates and metadata of atom in the homebox) as well as the output (i.e, forces on that atom)
// to adjust for time-mismatch of the various pipelines. Is initiated with start_i2, and forceReady indicates that force data are ready 
// in the output FIFO.
//-Does nearest neighbor estimate not with an explicit nearest neighbor list (whose calculation would take the same effort as the force 
// calculation, but by dividing the neigboring boxes into 4*4*4 subboxes. The relevant nearest-neigbor subboxes for a given home-box 
// atom are taken from a pre-programmed LUT_Box_x. Could in principle also be a writeable BRAM, in which case it could be programmed
// at runtime (would probably not add any significant resources)
//-Format of LUT_Box_x: Contains 10 address bits; the 7 LSBs is a counter that can (in principle) adress 128 subboxes, the 3 MSBs is 
// the position in the home box. In principle, 3*2 bits would be needed for that, but positions {3,2} are complimentary to {0,1}, hence 
// only 3*1 bits are needed. Each data element contains 7 bits. The 6 LSBs label (x,y,z) in the neigboring box (this time really two bits 
// each), and the 1 MSB  label one of the two neigboring boxes in +/- x-direction. File is generated with ProduceNearestNeighborLUTs.nb.
//-Actual force calculation is done in an universal submodule ForceNonBond. Its latency is given by parameter nPipeForce in MDmachine. 
//

//DATE FLOW:
//
//Data in atomData initiate CalcStze1
//                                               lat2                            lat6
// +--------+   +----------+  (i1r,cntSubBox)  +-------+ (iBox,ix2,iy2,iz2)   +------------+  (nAtomSubBox,iBox,ix2,iy2,iz2)  +----------+
// |atomData|-->|CalcState1|------------------>|Lut_Box|--------------------->|  pipeline  |--------------------------------->|SubBoxFIFO|
// +--------+   +----------+                   +-------+                      +----------^-+                                  +-----^----+
//      |            |                                                          | npipe2 |                                          |
//      |            |               npipe1                                     +--------+                                          |
//      |            +--------------------------------------------------------------------------------------------------------------+
//      |
//      |         +-----------+        (nSubBox,metadata,x1,y1,z1)
//      +-------->|miniFIFO1,2|-------------------------------------------------------+
//                +-----------+                                                       |
//                                                                                    |
//                                                                                    |
//Data in SubBoxFIFO initiate CalcState2:                                             |
//                                                             lat5                   | lat2
// +----------+   +----------+  (ix2,iy2,iz2,iAtomSubBox)  +-----------+ (x2,y2,z2) +----------+  (dx,dy,dz) +------------+    +-----+
// |SubBoxFIFO|-->|CalcState2|---------------------------->|NeighborBox|----------->| pipeline |------------>|ForceNonBond|--->|Force|
// +----------+   +----------+                             +-----------+            +-^--------+             +-----^------+    +-^---+
//                     |                     npipe3                                   |                            |             |
//                     +--------------------------------------------------------------+                            |             |
//                     |                              nPipe_ResetFtot, nPipe_AddFtot                               |             |
//                     +-------------------------------------------------------------------------------------------+             |
//                     |                                      nPipe_StoreFtot                                                    |
//                     +---------------------------------------------------------------------------------------------------------+
//
//

module ForceBox1
#(   
parameter nPipeForce      = 19,     //latency of force-calculation in ForceNonBond. All other latencies are derived from it.
parameter DataByteWidth_n = 5'd18,  //width of the memories containing neigboring box data, i.e., coordinates and meta-data
parameter ForceLUTWidth   = 9,      //length of Force LUT data line
parameter q0              = 0,      //ordering of the data, so that subroutine can be used for x-, y- or z-directions.
parameter q1              = 1,      //Swap at most two numbers and keep one constant, e.g, (2,1,3) but not (2,3,1),
parameter q2              = 2       //otherwise, cannot be inverted easily
)
(
input                                 IOclk,
input                                 CalcClk, 
//input that writes into Force-LUT
 input                                wrForceLUT,    
 input      [ForceLUTWidth*8-1:0]     dataForceLUT,  
 input      [8:0]                     adrForceLUT,   
 input                                selForceLUT,       
//write into Neigboring Box BRAM
input                                 data_valid_p,        //data valid for the right box
input                                 data_valid_n,        //data valid for the left box
input                                 iHalf,               //iHalf on IOclk
input         [7:0]                   nAtom_p,             //total number of data in right box, is a running index during writing
input         [7:0]                   nAtom_n,             //total number of data in right box, is a running index during writing
input         [DataByteWidth_n*8-1:0] data_p,              //data for the right box
input         [DataByteWidth_n*8-1:0] data_n,              //data for the left box
input                                 nAtomReset,          //reset nAtomSubBox_*, number of data in the various sub-boxes
output                                overflowSubbox,      //error upon overflow in one of the subboxes
//Calculation pipeline
input                                 iHalf_CalcClk,       //iHalf on CalcClk for reading
input                                 start_i2,            //(x1,y1,z1)-data ready to write into input FIFO
input         [DataByteWidth_n*8-1:0] dataHome,            //(x1,y1,z1)-data, contains coordinates and metadata
output                                forceReady,          //force calculation done
input                                 fifoOut,             //trigger output FIFO to send data
output        [95:0]                  forceFifo,           //calculated forces
output                                slowDown,            //input FIFO almost full, tell master pipeline to slow down
//for sending data to MAC/host computer
input                                 CalcBussy,           //CalcBussy, on CalcClk
input                                 SendMacHalf,         //memory half to be sent, on CalcClk
input        [7:0]                    SendMacAdr,           //adress of data to be sent, on CalcClk  
output       [DataByteWidth_n*8-1:0]  dataBox_p,
output       [DataByteWidth_n*8-1:0]  dataBox_n
);

localparam   nSubBoxTot      = 64;
localparam   width_iBox      = 1;                   //will chnage for different versions of subroutine
localparam   width_LUTBox    = width_iBox+6;
localparam   widthFIFOBox    = width_iBox+11;

localparam   nPipe1          = 8;                   //length of pipeline from cntSubBox to SubBoxFIFO_in 
localparam   nPipe2          = 3;                   //length of pipeline from LUT_Box out to SubBoxFIFO_in
localparam   nPipe3          = 4;                   //length of pipeline from SubBoxFIFO out to dataBox_* out
localparam   nPipe_AddFtot   = nPipeForce+4;        //latency of reading data plus ForceNonBond;
localparam   nPipe_ResetFtot = nPipeForce+5;        //timing of ResetFtot and StoreFtot; both signals should come at the same time 
localparam   nPipe_StoreFtot = nPipeForce+7;        //at the end of the 2-cycle addForce break. 



reg         [1:0]                   CalcState1 = 1'b0,CalcState2 = 1'b0;
reg         [6:0]                   cntSubBox  = 1'b0, cntSubBox2 = 1'b0;  
reg         [2:0]                   i1 = 1'b0; 
reg         [1:0]                   ix2[nPipe2:0];
reg         [1:0]                   iy2[nPipe2:0];
reg         [1:0]                   iz2[nPipe2:0];
reg         [nPipe_ResetFtot:0]     ResetFtot   = 1'b0;    
reg         [nPipe_StoreFtot:0]     StoreFtot   = 1'b0;             
reg         [width_iBox-1:0]        iBox[nPipe2:0];    
reg         [width_iBox-1:0]        iBox2[nPipe3:0];                     
wire                                FIFO2DataReady;
wire                                FIFO2AlmostFull;  
reg         [nPipe1:0]              FIFO2Write    = 1'b0; 
reg                                 FIFO2Read     = 1'b0;
reg                                 miniFIFOWrite = 1'b0;
reg         [nPipe3+2:0]            miniFIFORead  = 1'b0;
//wire        [DataByteWidth_n*8-1:0] dataBox_p;
//wire        [DataByteWidth_n*8-1:0] dataBox_n;
wire        [nSubBoxTot*4-1:0]      nAtomSubBox_p;
wire        [nSubBoxTot*4-1:0]      nAtomSubBox_n;
reg         [31:0]                  nAtomSubBox_n_d0;
reg         [31:0]                  nAtomSubBox_p_d0;
reg         [3:0]                   nAtomSubBox_n_d1;
reg         [3:0]                   nAtomSubBox_p_d1;
reg         [3:0]                   nAtomSubBox = 1'b0;
reg                                 fifoDataOut = 1'b0;          
reg         [6:0]                   writeFIFO   = 1'b0, writeFIFO_d0 = 1'b0;        
reg         [6:0]                   readFIFO    = 1'b0;
wire                                overflowSubbox_n, overflowSubbox_p;



   
wire [6:0] nSubBox [0:7];
assign nSubBox[0]=7'd77;     //Number of SubBoxes -1
assign nSubBox[1]=7'd77;
assign nSubBox[2]=7'd79;
assign nSubBox[3]=7'd79;
assign nSubBox[4]=7'd79;
assign nSubBox[5]=7'd79;
assign nSubBox[6]=7'd79;
assign nSubBox[7]=7'd79;


//******************************input data FIFO************************
//resuffle data so that subroutine can be used for x,y,z directions; add one buffer stage for better routing
reg [DataByteWidth_n*8-1:0] dataHomeReshuffle;
reg                         start_i2_d0;
always @(posedge CalcClk) begin
  dataHomeReshuffle <= {dataHome[DataByteWidth_n*8-1:72],dataHome[24*q2 +:24],dataHome[24*q1 +:24],dataHome[24*q0 +:24]};
  start_i2_d0       <= start_i2;
end

//has an almost-full option, that will tell the master-pipeline in MDmachine to slow down. Will msot likely never be needed but 
//avoids the need of an error signal
wire        [DataByteWidth_n*8-1:0] dataBoxFifo;
FIFO_144x64_singleClk atomData (
  .clk(CalcClk),      
  .din(dataHomeReshuffle),      
  .wr_en(start_i2_d0),  
  .rd_en(fifoDataOut),  
  .dout(dataBoxFifo),    
  .full(),    
  .empty(atomDataReady),  
  .prog_full(slowDown)
);

//*****************************************************************state machine 1*********************************************************
//generates a stream of (nAtomSubBox,iBox,iz2,iy2,ix2) that is fed into a FIFO and ultimately processed by state machine 2.
//The stream is output with CalcClk without waiting cycles. nAtomSubBox has a significant latency relative to iz2,iy2,ix2, hence the latter
//need to be delayed accordingly to be synchronized. Due to that latency, one cannot process data directly in one statemachine without 
//significant number of wait cycles. State machine 2 reads that stream, and can process data with in essence no wait cycles. Whenever some 
//nAtomSubBox>1, it will be slower than state machine 1, and there is a slow-down mechanism for state machine 1. 

wire        [1:0]     ix1  = dataBoxFifo[24*0+20 +:2];                //subbox in homebox
wire        [1:0]     iy1  = dataBoxFifo[24*1+20 +:2]; 
wire        [1:0]     iz1  = dataBoxFifo[24*2+20 +:2];  
wire        [2:0]     i1r  = {iz1[0]^ iz1[1],iy1[0]^ iy1[1],ix1[0]^ ix1[1]}; //reduce subboxnumber 0...3 to only 0...1, since it is symmetric, i.e., 3eq0 and 2eq1.
integer i;
always @(posedge CalcClk) begin
    for(i=1;i<=nPipe1;i=i+1) begin 
      FIFO2Write[i]<=FIFO2Write[i-1];
    end  
//state machine 1   
    case (CalcState1)
      0: begin
        if(~atomDataReady) begin
          fifoDataOut  <= 1'b1;
          CalcState1   <= 3'd1;
        end
      end  
      1: begin                     //wait for latency of FIFO
        fifoDataOut    <= 1'b0;
        CalcState1     <= 3'd2;
      end    
      2: begin                     //atom 1 data ready
        cntSubBox      <= 1'b0; 
        i1             <= {iz1[1],iy1[1],ix1[1]};  
        FIFO2Write[0]  <= 1'b1;
        miniFIFOWrite  <= 1'b1;
        CalcState1     <= 3'd3;
      end    
      3: begin
        miniFIFOWrite  <= 1'b0;
        if(cntSubBox==nSubBox[i1r]) begin        
          CalcState1       <= 3'd0;
          FIFO2Write[0]    <= 1'b0;
        end else begin 
          if(FIFO2AlmostFull) begin
            FIFO2Write[0]  <= 1'b0;
          end else begin
            FIFO2Write[0]  <= 1'b1;  
            cntSubBox      <= cntSubBox + 1'b1;
          end   
        end  
      end  
    endcase 
end          

//*******************miniFIFOs to store number of boxes, coordinates and meta data
//has space for two entries only
wire [6:0] nSubBox_FIFO;
miniFIFO #(.width (7)) miniFIFO1
(
  .clk   (CalcClk),      
  .din   (nSubBox[i1r]),      
  .wr_en (miniFIFOWrite),  
  .rd_en (miniFIFORead[0]),  
  .dout  (nSubBox_FIFO)  
);

wire [71:0] atom1_FIFO;            //eventually, size should be DataByteWidth_n*8
miniFIFO #(.width (72)) miniFIFO2
(
  .clk   (CalcClk),      
  .din   (dataBoxFifo[71:0]),      
  .wr_en (miniFIFOWrite),  
  .rd_en (miniFIFORead[nPipe3+2]),  
  .dout  (atom1_FIFO)  
);

//*********************LUT that contains all sub-boxes that need to be considered within cut-off****************************
//starts from cntSubBox and reveals iBox, ix2, iy2 and iz2. Latency 2
wire        [width_LUTBox-1:0]      LUT_Box_out;   
LUT_Box_x LUT_Box_x (
  .clka(CalcClk),    
  .addra({i1r,cntSubBox}),  
  .douta(LUT_Box_out) 
);

//subsequent pipeline starts from LUT_Box_out, determines iBox, ix2, iy2iz2, and nAtomSubbox and writes that into SubBoxFIFO 
wire   [2:0]                 adr0_nAtomSubbox={iz2[0],iy2[0][1]};
wire   [2:0]                 adr1_nAtomSubbox={iy2[1][0],ix2[1]};
reg    [widthFIFOBox-1:0]    FIFO_Box_in, FIFO_Box_in_d0; 
always @(posedge CalcClk) begin
    for(i=1;i<=nPipe2;i=i+1) begin 
      iBox[i]<=iBox[i-1];
      ix2[i] <= ix2[i-1];
      iy2[i] <= iy2[i-1];
      iz2[i] <= iz2[i-1];
    end  
//level 1 of pipeline
    iBox[0] <= i1[width_iBox-1:0]^LUT_Box_out[width_iBox+5:6];
    ix2[0]  <= i1[0] ? 2'd3-LUT_Box_out[1:0] : LUT_Box_out[1:0];
    iy2[0]  <= i1[1] ? 2'd3-LUT_Box_out[3:2] : LUT_Box_out[3:2];
    iz2[0]  <= i1[2] ? 2'd3-LUT_Box_out[5:4] : LUT_Box_out[5:4];
//level 2 of pipeline
//separate multiplexer into 3 stages
    nAtomSubBox_n_d0 <= nAtomSubBox_n[adr0_nAtomSubbox*32+:32];   
    nAtomSubBox_p_d0 <= nAtomSubBox_p[adr0_nAtomSubbox*32+:32];  
//level 3 of pipeline
    nAtomSubBox_p_d1 <= nAtomSubBox_p_d0[adr1_nAtomSubbox*4+:4];
    nAtomSubBox_n_d1 <= nAtomSubBox_n_d0[adr1_nAtomSubbox*4+:4];  
//level 4 of pipeline 
    case (iBox[nPipe2-1])
      0: nAtomSubBox <=  nAtomSubBox_n_d1;
      1: nAtomSubBox <=  nAtomSubBox_p_d1;
    endcase  
//level 5 of pipeline  
    FIFO_Box_in      <=  {(nAtomSubBox!=0),((nAtomSubBox==0)? 3'b0: nAtomSubBox-1'b1),iBox[nPipe2],iz2[nPipe2],iy2[nPipe2],ix2[nPipe2]};  
//level 6 of pipeline  
    FIFO_Box_in_d0   <= FIFO_Box_in;   //for easier routing
end 

wire  [widthFIFOBox-1:0] FIFO_Box_out;
wire  [1:0]              ix2_FIFO         = FIFO_Box_out[1:0];
wire  [1:0]              iy2_FIFO         = FIFO_Box_out[3:2];
wire  [1:0]              iz2_FIFO         = FIFO_Box_out[5:4];
wire  [width_iBox-1:0]   iBox_FIFO        = FIFO_Box_out[width_iBox+5:6];
wire  [3:0]              nAtomSubBox_FIFO = FIFO_Box_out[width_iBox+9:width_iBox+6];
wire                     noAtom           = FIFO_Box_out[width_iBox+10];
reg   [3:0]              iAtomSubBox      = 1'b0;
wire                     FIFO2Read_d0     = FIFO2Read&&(iAtomSubBox==nAtomSubBox_FIFO);
FIFO_Box_x SubBoxFIFO
(
  .clk(CalcClk),      
  .din(FIFO_Box_in_d0),      
  .wr_en(FIFO2Write[nPipe1]),  
  .rd_en(FIFO2Read_d0),  
  .dout(FIFO_Box_out),    
  .full(),    
  .empty(FIFO2DataReady),
  .prog_full(FIFO2AlmostFull)  
);

//*********************************************state machine 2****************************************
//process synchronized (nAtomSubBox,iBox,iz2,iy2,ix2) stream

reg                   next_cnt2 =1'b0;                  
reg [nPipe_AddFtot:0] addForce  =1'b0;
always @(posedge CalcClk) begin
  ResetFtot    <= {ResetFtot[nPipe_ResetFtot-1:0],ResetFtot[0]}; 
  StoreFtot    <= {StoreFtot[nPipe_StoreFtot-1:0],StoreFtot[0]}; 
  addForce     <= {addForce[nPipe_AddFtot-1:0],addForce[0]};
  miniFIFORead <= {miniFIFORead[nPipe3+1:0],miniFIFORead[0]};
  iBox2[0]     <= iBox_FIFO;
  for(i=1;i<=nPipe3;i=i+1) begin 
    iBox2[i]        <=iBox2[i-1];
  end  
 
  case (CalcState2)
    0: begin
      addForce[0]      <= 1'b0;
      cntSubBox2       <= 1'b0;
      if(~FIFO2DataReady) begin
        CalcState2     <= 3'd1;
        FIFO2Read      <= 1'b1;
        ResetFtot[0]   <= 1'b0;
      end  else begin
        ResetFtot[0]   <= 1'b1;
      end
    end
    1: begin
      addForce[0]      <= noAtom;
      if(iAtomSubBox<nAtomSubBox_FIFO) begin
        iAtomSubBox    <= iAtomSubBox +1'b1;
      end else begin
        iAtomSubBox    <= 1'b0;
        cntSubBox2     <= cntSubBox2 + 1'b1;
        next_cnt2      <= (cntSubBox2 == nSubBox_FIFO -1'b1);       //precalculate
        if(next_cnt2) begin
          miniFIFORead[0] <= 1'b1;
          FIFO2Read       <= 1'b0;
          StoreFtot[0]    <= 1'b1;
          CalcState2      <= 3'd2;
        end 
      end      
    end
    2: begin
      StoreFtot[0]     <= 1'b0;
      addForce[0]      <= 1'b0;
      miniFIFORead[0]  <= 1'b0;
      ResetFtot[0]     <= 1'b1;
      CalcState2       <= 3'd0;
    end
  endcase  
end

//************************************Memories for neighboring boxes*******************************************
//Reads atom data based on (iz2,iy2,ix2,nAtomWork) input, latency 4.
//The data that are written into memory are reshuffled in a way that subroutine can be used for x,y,z directions, 
//depending on parameters q0,q1,and q2.
//In addition, shift coordinates by one box size already now
wire [DataByteWidth_n*8-1:0] data_nReshuffle = {data_n[DataByteWidth_n*8-1:72],data_n[24*q2 +:24],data_n[24*q1 +:24],(data_n[24*q0 +:24]-24'h400000)};
NeighborBox
#(  
.DataByteWidth_n (DataByteWidth_n)
) NeighborBox_n  //left box
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write into BRAM and sub-box LUT
.data_valid     (data_valid_n),                             //input data valid
.iHalf          (iHalf),                                    //iHalf on IOclk for writing
.dataIn         (data_nReshuffle),                          //input data, contains positions and meta data
.nAtomReset     (nAtomReset),                               //reset nAtomSubBox
.nAtom          (nAtom_n),                                  //input, number of data in whole box, is a running index during writing
.overflowSubbox (overflowSubbox_n),                         //indicates that one of the subboxes contains >16 entries (in average should be <4)
//read Data
.iHalf_CalcClk  (iHalf_CalcClk),                            //iHalf on CalcClk for reading
.nAtomSubBox    (nAtomSubBox_n),                            //output, number of data in the various sub-boxes
.readEn         (1'b1),                                      //used to be ~iBox_FIFO, to save power if not used                                
.iAtomSub       ({iz2_FIFO,iy2_FIFO,ix2_FIFO,iAtomSubBox}), //address atom, NEW
.dataBox        (dataBox_n),                                 //outout data, contains positions and meta-data
//read Data for MAC/host compuer
.CalcBussy      (CalcBussy),                                 //CalcBussy, on CalcClk
.SendMacHalf    (SendMacHalf),                               //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);

wire [DataByteWidth_n*8-1:0] data_pReshuffle = {data_p[DataByteWidth_n*8-1:72],data_p[24*q2 +:24],data_p[24*q1 +:24],(data_p[24*q0 +:24]+24'h400000)};
NeighborBox  //right box
#(  
.DataByteWidth_n (DataByteWidth_n),
.nSubBoxTot      (nSubBoxTot)
) NeighborBox_p
(
.IOclk          (IOclk),
.CalcClk        (CalcClk),
//write into BRAM and to sub-box LUT
.data_valid     (data_valid_p),                             //input data valid
.iHalf          (iHalf),                                    //iHalf on IOclk for writing
.dataIn         (data_pReshuffle),                          //input data, contains positions and meta data
.nAtomReset     (nAtomReset),                               //reset nAtomSubBox
.nAtom          (nAtom_p),                                  //input, number of data in whole box, is a running index during writing
.overflowSubbox (overflowSubbox_p),                         //indicates that one of the subboxes contains >16 entries (in average should be <4)
//read Data
.iHalf_CalcClk  (iHalf_CalcClk),                            //iHalf on CalcClk for reading
.nAtomSubBox    (nAtomSubBox_p),                            //output, number of data in the various sub-boxes
.readEn         (1'b1),                                     //used to be iBox_FIFO, to save power if not used 
.iAtomSub       ({iz2_FIFO,iy2_FIFO,ix2_FIFO,iAtomSubBox}), //address atom, NEW
.dataBox        (dataBox_p),                                 //outout data, contains positions and meta-data
//read Data for MAC/host compuer
.CalcBussy      (CalcBussy),                                 //CalcBussy, on CalcClk
.SendMacHalf    (SendMacHalf),                               //memory half to be sent, on CalcClk
.SendMacAdr     (SendMacAdr)                                 //adress to be sent, on CalcClk  
);
assign overflowSubbox = overflowSubbox_p||overflowSubbox_n;  //will produce an errorsignal

//subsequent pipeline starts from dataBox_* from NeighborBox_*
wire signed [23:0]    x1   = atom1_FIFO[24*0 +:24];
wire signed [23:0]    y1   = atom1_FIFO[24*1 +:24];
wire signed [23:0]    z1   = atom1_FIFO[24*2 +:24];
reg  signed [23:0]    dx = 1'b0, dy = 1'b0, dz = 1'b0;
reg  signed [23:0]    x2 = 1'b0, y2 = 1'b0, z2 = 1'b0;
always @(posedge CalcClk) begin
    x2              <= iBox2[nPipe3] ? dataBox_p[24*0 +:24] : dataBox_n[24*0 +:24]; 
    y2              <= iBox2[nPipe3] ? dataBox_p[24*1 +:24] : dataBox_n[24*1 +:24];
    z2              <= iBox2[nPipe3] ? dataBox_p[24*2 +:24] : dataBox_n[24*2 +:24];
//level 1 of pipeline    
    dx              <= x2-x1;  
    dy              <= y2-y1;
    dz              <= z2-z1;  
//force calculation in ForceNonBond starts from here    
end

wire signed [31:0]   Fx_tot,Fy_tot,Fz_tot;
ForceNonBond 
#(
.ForceLUTWidth   (ForceLUTWidth)
)ForceNonBond
(
.IOclk        (IOclk),
.CalcClk      (CalcClk),
.wrForceLUT   (wrForceLUT),    
.dataForceLUT (dataForceLUT),  
.adrForceLUT  (adrForceLUT),   
.selForceLUT  (selForceLUT),    
.ResetFtot    (ResetFtot[nPipe_ResetFtot]),
.pipe         (addForce[nPipe_AddFtot]),
.dx           (dx),
.dy           (dy),
.dz           (dz),
.Fx_tot       (Fx_tot),
.Fy_tot       (Fy_tot), 
.Fz_tot       (Fz_tot)
);

//re-reshufle calculated forces so that that subroutine can be used for x,y,z directions
wire  [95:0] F_totReshuffle;
assign F_totReshuffle[32*q0 +:32] = Fx_tot;
assign F_totReshuffle[32*q1 +:32] = Fy_tot;
assign F_totReshuffle[32*q2 +:32] = Fz_tot;

//store results in output FIFO, for later ussage
FIFO_96x64 Force1 (
  .wr_clk(CalcClk),    
  .rd_clk(IOclk),        
  .din(F_totReshuffle),      
  .wr_en(StoreFtot[nPipe_StoreFtot]),     
  .rd_en(fifoOut),  
  .dout(forceFifo),    
  .full(),            //should never become full due to slowDown logic
  .empty(forceReady)  
);


endmodule
