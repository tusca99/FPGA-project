`timescale 1ns / 1ps

//Collects all errors, and writes them into one word errorAll. Lowest byte (Bit0-Bit7) contains errors that go on and off 
//(such as fan_error) and are just wired through. Other errors are single clock-cycle events and are stored in a register. 
//error_reset resets them
//
//Bit:
//0:        Fan not running
//1:        ETH3 not connected
//2:        ETH3, speed <1Gb/s
//3:        ETH4 not connected
//4:        ETH4, speed <1Gb/s
//5:        reserve
//6:        reserve
//7:        reserve
//8:        ETH3, tx FIFO overflow
//9:        ETH3, rx crc-error 
//10:       ETH3, rx seq-error 
//11:       ETH3, rx ecc correction    
//12:       ETH4, tx FIFO overflow
//13:       ETH4, rx crc-error
//14:       ETH4, rx seq-error
//15:       ETH4, rx ecc correction  
//16:       gtp0, tx FIFO overflow
//17:       gtp1, tx FIFO overflow
//18:       gtp2, tx FIFO overflow
//19:       gtp3, tx FIFO overflow
//20:       gtp0, tx MUX overflow
//21:       gtp1, tx MUX overflow
//22:       gtp2, tx MUX overflow
//23:       gtp3, tx MUX overflow
//24:       gtp0, rx error (crc or sequence_cnt)
//25:       gtp1, rx error (crc or sequence_cnt)
//26:       gtp2, rx error (crc or sequence_cnt)
//27:       gtp3, rx error (crc or sequence_cnt)
//28:       GatedMuxError in BrodcstAtom.v
//29:       Homebox overflow
//30:       Neigboring box overflow
//31:       sub box overflow
//32-47:    reserve
//
//errorRxCnt:
//0:        //ETH3 crc-error
//1:        //ETH3 seq-error
//2:        //ETH3 ecc correction
//3:        //ETH4 crc-error
//4:        //ETH4 seq-error
//5:        //ETH4 ecc correction
//4:        //gtp0 seq or crc-error
//5:        //gtp0 seq or crc-error
//6:        //gtp0 seq or crc-error
//7:        //gtp0 seq or crc-error

module ErrorHandler
    (
    input             clk,
    input             error_reset,
    input             errorRxReset,  
    input      [1:0]  ReNegotiateETH34,
    input             fan_error,
    input      [1:0]  speed3,
    input      [1:0]  speed4,
    input      [7:0]  ETH_error,   //used to be [3:0]
    input      [11:0] gtp_error,
    input             GatedMuxError,   
    input      [2:0]  overflowError,              
    output     [47:0] errorAll,               //used to be [63:0]
    output reg        errorRxSync,   
    output reg [79:0] errorRxCnt=1'b0         //used to be [47:0]   
    );

reg [39:0] errorReg=1'b0;
//wire [9:0] cnt_rx    =   {gtp_error[11:8],ETH_error[7],ETH_error[6],ETH_error[5],ETH_error[3],ETH_error[2],ETH_error[1]};   //collect all receiving errors and warning; in case of ETH, three signals each for ECC, sequence and crc error
 
integer i;
always @(posedge clk) begin
  if(error_reset)  begin
    errorReg    <= 1'b0;    
    errorRxCnt  <= 1'b0;
    errorRxSync <= 1'b0;
  end else if (errorRxReset) begin
    errorReg[7:0]  <= errorReg[7:0]  & 8'b10011001;  //reset ETH rx-errors 
    errorReg[19:8] <= errorReg[19:8] & 12'h0ff;      //reset gtp rx-errors
    errorRxSync    <= 1'b0;
  end else if (ReNegotiateETH34!=2'b0) begin  
    if (ReNegotiateETH34[0]) errorRxCnt[0+:16]  <= 1'b0;
    if (ReNegotiateETH34[1]) errorRxCnt[24+:16] <= 1'b0;
  end else begin
    errorReg[7:0]   <= errorReg[7:0]  | ETH_error;
    errorReg[19:8]  <= errorReg[19:8] | gtp_error; 
    errorReg[20]    <= errorReg[20]   | GatedMuxError; 
    errorReg[23:21] <= errorReg[23:21]| overflowError; 
    if(gtp_error[11]||gtp_error[10]||gtp_error[9]||gtp_error[8]||ETH_error[6]||ETH_error[5]||ETH_error[2]||ETH_error[1]) errorRxSync <= 1'b1;
    if(ETH_error[1])  errorRxCnt[0*8+:8] <= errorRxCnt[0*8+:8] +1'b1;
    if(ETH_error[2])  errorRxCnt[1*8+:8] <= errorRxCnt[1*8+:8] +1'b1;
    if(ETH_error[3])  errorRxCnt[2*8+:8] <= errorRxCnt[2*8+:8] +1'b1;
    if(ETH_error[5])  errorRxCnt[3*8+:8] <= errorRxCnt[3*8+:8] +1'b1;
    if(ETH_error[6])  errorRxCnt[4*8+:8] <= errorRxCnt[4*8+:8] +1'b1;
    if(ETH_error[7])  errorRxCnt[5*8+:8] <= errorRxCnt[5*8+:8] +1'b1;
    if(gtp_error[8])  errorRxCnt[6*8+:8] <= errorRxCnt[6*8+:8] +1'b1;
    if(gtp_error[9])  errorRxCnt[7*8+:8] <= errorRxCnt[7*8+:8] +1'b1;
    if(gtp_error[10]) errorRxCnt[8*8+:8] <= errorRxCnt[8*8+:8] +1'b1;
    if(gtp_error[11]) errorRxCnt[9*8+:8] <= errorRxCnt[9*8+:8] +1'b1;       
  end      
end
assign errorAll={errorReg,3'b0,(speed4!=2'b11),(speed4==2'b00),(speed3!=2'b11),(speed3==2'b00),fan_error};
  
endmodule
