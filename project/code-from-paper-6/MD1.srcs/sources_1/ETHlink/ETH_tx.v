`timescale 1ns / 1ps

//-use ETH3 and ETH4 as 1Gb link to the nodes up and down. 
//-Protocol: preamble (7*8'h55, 8'hd5), data (nETH Byte), sequence count (1byte), crc (3 byte), framegap (12 byte)
//-All except of preamble and framegap are chopped into 4byte pieces, run through a ECC with 1byte added for error correction.
// Error correction also includes sequence count and crc
//-In total 8*nETH/4*5+5+12=60 clock cycles for one data set, which matches exactly what the GTP needs (i.e., 10 clock cycles, 
// but need to transmit 6 data sets in the same time) 
//-is complementary to ETH_rx
//- has FIFO at the input sufficient for 128 lines (same as gtp_tx). 64 would be better in terms of LUT-Ram
// usage, but had overflows at some point (might have changed due to slower calculation in MDmachine)
//
//input:  
//tx_req       request to send data
//data_send    data to be sent
//
//output:
//tx_error     error upon FIFO overflow
//bussy        bussy signal

module ETH_tx
#(
parameter nETH  =           5'd28  //length of a data line
)
(
     input                   ErrorReset,
     input                   e_clk,   
     input                   IOclk,   
     output reg              e_tx_en,
     output reg [7:0]        e_txd, 
     input      [nETH*8-1:0] data_send,
     input                   tx_req,
     output                  tx_error,
     output reg              bussy=1'b0
);
 
localparam ExtendBussy_ETHtx=7'd127;   //extend busy signal of ETH_tx to account for latency of ETH chip; used to be 63, sync error, increasd to 127, worked, but dont think was the problem
//(* MARK_DEBUG="true" *) 
 
reg  [5:0]            frame_cnt      = 1'b0;  
wire [7:0]            e_txd_d0;       
reg  [7:0]            e_txd_d1       = 1'b0;
reg                   e_tx_en_d1     = 1'b0;
reg  [7:0]            e_txd_d2       = 1'b0;
reg                   e_tx_en_d2     = 1'b0;
reg  [7:0]            e_txd_d3       = 1'b0;
reg                   e_tx_en_d3     = 1'b0;
reg                   crc_en         = 1'b0;
wire [23:0]           crc;
reg                   FIFO_rd        = 1'b0;
wire [nETH*8-1:0]     data_FIFO_out;
reg                   FIFO_wr        = 1'b0;
reg  [3:0]            data_cnt       = 1'b0;
reg  [nETH*8-1:0]     outbuff        = 1'b0;
reg  [39:0]           outbuff2       = 1'b0;
reg  [7:0]            sequence_cnt   = 1'b1;  //1
wire                  FIFO_empty; 
reg                   bussy_d0       = 1'b0;
wire                  bussy_d2;       
reg  [2:0]            state1         = 1'b0;
wire [31:0]           ecc_data;
wire [6:0]            ecc_chkbits; 
reg  [3:0]            cnt1           = 1'b0;
reg  [2:0]            cnt2           = 1'b0;
reg  [2:0]            cnt3           = 1'b0;
reg                   ecc_src        = 1'b0;



//*************************************input FIFO********************************

FIFO_224x128 FIFO_ETH_tx (         //input FIFO, latency 1, 
  .wr_clk(IOclk),             
  .rd_clk(e_clk),  
  .din(data_send),        
  .wr_en(tx_req),    
  .rd_en(FIFO_rd),    
  .dout(data_FIFO_out),      
  .full(tx_error),  
  .empty(FIFO_empty)    
); 




//************************************send data************************************

assign e_txd_d0=outbuff2[39:32];
always @(posedge e_clk) begin
//add FFs for better routing
   e_txd_d2      <= e_txd_d1; 
   e_tx_en_d2    <= e_tx_en_d1; 
   e_txd_d3      <= e_txd_d2; 
   e_tx_en_d3    <= e_tx_en_d2; 
   e_txd         <= e_txd_d3;       
   e_tx_en       <= e_tx_en_d3;
//shift out data  
   if(cnt1==3'd1) outbuff2 <= {ecc_data,1'b0,ecc_chkbits};
   else           outbuff2 <= {outbuff2[31:0],8'b0}; 
//produce preamble and combine with data
   if(state1==0) frame_cnt <= 1'b0;
   else          frame_cnt <= frame_cnt + 1'b1;
   if (frame_cnt==7'd0)      begin    
     e_txd_d1   <= 1'b0;
     e_tx_en_d1 <= 1'b0;
   end else if (frame_cnt<7'd8)  begin 
     e_txd_d1    <= 8'h55;
     e_tx_en_d1  <= 1'b1;
   end else if (frame_cnt==7'd8)  e_txd_d1   <= 8'hd5;
   else                           e_txd_d1   <= e_txd_d0;
   if (frame_cnt==(nETH/4+1)*5+9) e_tx_en_d1 <= 1'b0;
//main state machine  
   if (ErrorReset) sequence_cnt <= 1'b1;
   else begin
     case (state1)
       0: begin
        crc_en       <= 1'b0;
        cnt1         <= 1'b0;
        cnt2         <= 1'b0;
        cnt3         <= 1'b0;
        ecc_src      <= 1'b0;
        bussy_d0     <= 1'b0;
        if(~FIFO_empty) begin 
          state1     <= 3'd1;
        end  
       end
       1: begin               //wait for the preamble
         bussy_d0    <= 1'b1;
         cnt3 <= cnt3+1'b1;
         if(cnt3==3'h4) begin   
           FIFO_rd   <= 1'b1;
           state1    <= 3'd2;
         end   
       end
       2: begin
         FIFO_rd  <= 1'b0;
         state1   <= 3'd3;
       end
       3: begin
         outbuff  <= data_FIFO_out;
         crc_en   <= 1'b1;
         state1   <= 3'd4;
       end
       4: begin
         if(cnt1==3'd4) begin
           if(cnt2==nETH/4-1) begin
             cnt1    <= 1'b0;
             state1  <= 3'd5;
             ecc_src <= 1'b1;
           end else begin
             cnt2    <= cnt2 +1'b1;
             cnt1    <= 1'b0;
             crc_en  <= 1'b1;
             outbuff <= {outbuff[nETH*8-33:0],32'b0};
           end  
         end else begin
           crc_en   <= 1'b0;
           cnt1     <= cnt1+1'b1;
         end   
       end
       5: begin       //interpacket gap     
         cnt1         <= cnt1+1'b1; 
         if(cnt1==4'hf) begin   
           sequence_cnt <= sequence_cnt + 1'b1;
           state1       <= 3'd0;
         end  
       end
     endcase  
   end
end    




crc24 crc1 
(
.Clk      (e_clk), 
.Reset    (FIFO_rd),
.d        (outbuff[nETH*8-1:nETH*8-32]),
.Enable   (crc_en), 
.c        (crc)
); 


EECEncode eec1 (
  .ecc_data_in     ( ecc_src ? {sequence_cnt,crc} : outbuff[nETH*8-1:nETH*8-32]),
  .ecc_data_out    (ecc_data),
  .ecc_chkbits_out (ecc_chkbits)
);



ClkTransferStat #(.Width (1))  ClkTransferStat  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (bussy_d0),
    .sigOut  (bussy_d2)
); 


//extend busy signal of ETH_tx by extra 400ns to account for latency of ETH chip 
reg  [6:0] DelayBussy_cnt=1'b0;
always @(posedge IOclk) begin
  if(bussy_d2==1'b1) begin
    DelayBussy_cnt <= 1'b0;
    bussy          <= 1'b1;
  end else begin
    if (DelayBussy_cnt<ExtendBussy_ETHtx) DelayBussy_cnt <= DelayBussy_cnt+1'b1;
    else                                  bussy          <= 1'b0;
  end  
end


endmodule
