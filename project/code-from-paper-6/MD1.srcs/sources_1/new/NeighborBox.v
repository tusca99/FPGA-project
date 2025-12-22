`timescale 1ns / 1ps

//Memory containing the atom data of neigboring boxes, which are organized in 4*4*4 sub-boxes. 
//- For writing, sub-box is determined based on the coordinates of the input data, and two memories are written in parallel: one containg 
//  the actual data, and a second one, which is addressed by sub-box index and which stores where in the first memory are the requested data  
//- For reading, data are adressed by the subbox index (ix,iy,iz, upper 6 bits of iAtomSub). Each subbox can store 16 data, given by the 
//  lower 4 bits of iAtomSub. 16 atoms should be enough given that the maximum average is 4. If there is an overflow, and error signal will
//  be generated.
//- Both memories are doubled and adreessed by iHalf in an alternating manner, in order to be able to write new data while old data are 
//  still processewd      
//- Overall latency from iAtomSub to dataBox is 5. 

 
module NeighborBox
#(   
parameter DataByteWidth_n = 5'd18,
parameter nSubBoxTot      = 64
)
(
input                                IOclk,
input                                CalcClk,
//write into Neigboring Box BRAM
input                                data_valid,           //input data valid
input                                iHalf,               //iHalf on IOclk for writing
input        [DataByteWidth_n*8-1:0] dataIn,               //input data, contains positions and meta data
input                                nAtomReset,           //reset nAtomSubBox
input        [7:0]                   nAtom,                //number of data in whole box, is a running index during writing
output reg                           overflowSubbox =1'b0, //indicates that one of the subboxes contains >16 entries (in average should be <4)
//read Data by MDmachine
input                                iHalf_CalcClk,        //iHalf on CalcClk for reading
output reg   [nSubBoxTot*4-1:0]      nAtomSubBox,          //number of data in the various sub-boxes output, on CalcClk
input                                readEn,               //avoid that the memory is active when not in use, to save electrical power
input        [9:0]                   iAtomSub,             //input, adress data to be read 
output       [DataByteWidth_n*8-1:0] dataBox,              //outout data, contains positions and meta-data
//for sending data to MAC/host computer
input                                CalcBussy,            //CalcBussy, on CalcClk
input                                SendMacHalf,          //memory half to be sent, on CalcClk
input        [7:0]                   SendMacAdr            //adress of data to be sent, on CalcClk  
);

wire   [5:0]              iSubBox    = {dataIn[69:68],dataIn[45:44],dataIn[21:20]};   //subbox 
wire   [7:0]              adrOut;                                                     //address in box BRAM
reg                       readEn_d0=1'b0,readEn_d1 = 1'b0; 
reg   [nSubBoxTot*4-1:0]  nAtomSubBoxAcc           = 1'b0;          //number of data in the various sub-boxes for accumulation
reg                       iHalf_store              = 1'b0;
reg                       store_nAtomSub_d0        = 1'b0;
reg                       iHalf_CalcClk_d0         = 1'b0;
reg   [8:0]               addrb                    = 1'b0;

ClkTransfer #(.extend (2)) ClkTransfer1
(
    .clkIn   (IOclk),
    .clkOut  (CalcClk),
    .sigIn   (nAtomReset),
    .sigOut  (nAtomReset_d1)
); 

ClkTransfer #(.extend (3)) ClkTransfer2
(
    .clkIn   (CalcClk),
    .clkOut  (IOclk),
    .sigIn   (nAtomReset_d1),
    .sigOut  (nAtomReset_d2)
);
 


always @(posedge IOclk) begin
  if(nAtomReset_d2)  begin 
    nAtomSubBoxAcc <= 1'b0;
    overflowSubbox <= 1'b0;  
  end  
  else begin 
    if(data_valid) begin 
      nAtomSubBoxAcc[iSubBox*4+:4]   <= nAtomSubBoxAcc[iSubBox*4+:4] + 1'b1;  
      if(nAtomSubBoxAcc[iSubBox*4+:4]==4'hf) overflowSubbox <= 1'b1;
    end  
  end   
end  

//wire iHalf_CalcClk_d0 = iHalf_CalcClk;
always @(posedge CalcClk) begin
  iHalf_CalcClk_d0 <= iHalf_CalcClk;         //for better routing
  if(nAtomReset_d1)  begin 
    iHalf_store    <= iHalf_CalcClk_d0;
    if(iHalf_store!=iHalf_CalcClk_d0) nAtomSubBox <= nAtomSubBoxAcc;   //transfer only when iHalf switched
  end  
end


//LUT of the atom# in the 64 subBoxes, latency 2
always @(posedge CalcClk) begin
  readEn_d0 <= readEn;
  readEn_d1 <= readEn_d0;       //exend a little bit before switching it off; to account for latency
end  
bram_8x2048 AtomLUT (.clka(IOclk),.ena(1'b1),.wea(data_valid),.addra({iHalf,iSubBox,nAtomSubBoxAcc[iSubBox*4+:4]}),.dina(nAtom),.clkb(CalcClk),.enb(readEn||readEn_d0||readEn_d1),.addrb({~iHalf_CalcClk_d0,iAtomSub}),.doutb(adrOut)); 

//memory containing the actual data, total latency (including mux) 3
always @(posedge CalcClk) begin
  addrb <= CalcBussy ? {~iHalf_CalcClk_d0,adrOut} : {SendMacHalf,SendMacAdr};  //mux that send mux data either to MDmachine or MAC/hostcomputer 
end
bram_144x512_simple_dual boxMemory (.clka(IOclk),.ena(1'b1),.wea(data_valid) ,.addra({iHalf,nAtom}),.dina(dataIn),.clkb(CalcClk),.enb(1'b1),.addrb(addrb),.doutb(dataBox));


endmodule
