`timescale 1ns / 1ps

module SyncNodes
    (
    input             IOclk,
    inout             AllBussyExt11,   
    inout             errorRxSyncExt11,
    inout             AllBussyExt12,   
    inout             errorRxSyncExt12,
    inout             AllBussyExt2,   
    inout             errorRxSyncExt2,  
    input             AllBussy,
    input             errorRxSync,
    output reg        AllBussyIn,
    output reg        errorRxSyncIn
    );


//When AllBussy is 1, it is output to AllBussyExt11, where all nodes are wired in parallel. Is set to 0 
//immedeatly, but to 1 delayed so that all nodes see the 0. The output is configured as biderectional 
//with pull-down resistor (internal as well as 2.2K external). When AllBussy is 1, AllBussyExt11 is 1. When it switches 
//to 0, it goes into high-impedance. On the receiving side, when all nodes on AllBussyExt1 are 
//0 for at least 7 clock cycles, it is considered to be a 0.
//
//In addition, there is a perpendicular network (AllBussyExt2), that connects various AllBussyExt1 strings.
//Since connecting it to AllBussyExt11 would lock it to 1 for ever, a second string AllBussyExt12 runs in 
//parralel to AllBussyExt11. The output is an OR of AllBussyExt11 and AllBussyExt11. Some signals need to be extended
//so that all nodes see it.
//The data flow is:
//  
//           11     12                            11     12
//           |      |                             |      | 
//           |      |                             |      | 
//           o->|   o<-|                          o->|   o<-|
//        ---|--o---|--o-------------2------------|--o---|--o---
//           |      |                             |      | 
//           |      |                             |      | 
// in local->o      |                   in local->o      |
//           |      |                             |      |
//           o------|->-|                         o------|->-|
//           |      |  OR -> out local            |      |   OR -> out local             
//           |      o->-|                         |      o->-|
//           |      |                             |      |
//
//
//Same is done for errorRxSync, without the initial wait for going high



reg       AllBussy_d0;
reg [5:0] AllBussyCnt1_1=1'b0, AllBussyCnt1_2=1'b0; 
reg [5:0] AllBussyCnt2=1'b0;  
reg       AllBussyExt11_d0;

always @(posedge IOclk) begin

  if(~(AllBussy)) begin          //set low immedeatly, but high delayed, so that all nodes see the 0
     AllBussyCnt1_1 <= 1'b0;
     AllBussy_d0    <= 1'b0;
  end else begin 
    if (AllBussyCnt1_1<6'h30) AllBussyCnt1_1 <= AllBussyCnt1_1 +1'b1;
    else                      AllBussy_d0    <= 1'b1;       
  end  
  
 if(~(AllBussyExt11)) begin          //set low immedeatly, but high delayed, so that all nodes see the 0
     AllBussyCnt1_2   <= 1'b0;
     AllBussyExt11_d0 <= 1'b0;
  end else begin 
    if (AllBussyCnt1_2<6'h30) AllBussyCnt1_2   <= AllBussyCnt1_2 +1'b1;
    else                      AllBussyExt11_d0 <= 1'b1;       
  end  
 
end
 
assign AllBussyExt11 =  AllBussy_d0       ? 1'b1 : 1'bz;       
assign AllBussyExt2  =  AllBussyExt11_d0  ? 1'b1 : 1'bz;         
assign AllBussyExt12 =  AllBussyExt2      ? 1'b1 : 1'bz;        
        
                  
always @(posedge IOclk) begin                           //input needs to be low for at least 7 cycles to consider it low
  if(AllBussyExt11||AllBussyExt12) begin 
    AllBussyCnt2 <= 1'b0;
    AllBussyIn   <= 1'b1;
  end else begin 
    if (AllBussyCnt2<6'h7) AllBussyCnt2 <= AllBussyCnt2 +1'b1;
    else                   AllBussyIn   <= 1'b0;         
  end
end         



//***********************************************************same for error signal, without the initial wait

reg [2:0] errorRxSyncCnt2=1'b0; 



assign errorRxSyncExt11 = errorRxSync      ? 1'b1 : 1'bz;       
assign errorRxSyncExt12 = errorRxSyncExt2  ? 1'b1 : 1'bz;       
assign errorRxSyncExt2  = errorRxSyncExt11 ? 1'b1 : 1'bz;      
     

                  
always @(posedge IOclk) begin                           //input needs to be low for at least 7 cycles to consider it low
  if(errorRxSyncExt11||errorRxSyncExt12) begin 
    errorRxSyncCnt2 <= 1'b0;
    errorRxSyncIn   <= 1'b1;
  end else begin 
    if (errorRxSyncCnt2<3'h7)  errorRxSyncCnt2 <= errorRxSyncCnt2 +1'b1;
    else                       errorRxSyncIn   <= 1'b0;         
  end
end      


endmodule
