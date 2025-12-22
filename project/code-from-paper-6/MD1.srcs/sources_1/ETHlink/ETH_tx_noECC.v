`timescale 1ns / 1ps

//use ETH3 and ETH4 as 1Gb link to the nodes up and down. 
//protocol: 7*8'h55, 8'hd5, data (nETH Byte), sequence count (1byte), crc (4 byte), framegap (12 byte)
//complementary to ETH_rx
//has FIFO at the input sufficient for 128 lines (same as gtp_tx). 64 would be better in terms of LUT-Ram
//usage, but had overflows at some point (might have changed due to slower calculation in MDmachine)
//
//input:  
//tx_req       request to send data
//data_send    data to be sent
//
//output:
//tx_error     error upon FIFO overflow

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
     output reg              bussy
);
 
localparam ExtendBussy_ETHtx=6'd63;   //extend busy signal of ETH_tx by extra 800ns (used to be 500) to account for latency of ETH chip 
 
//(* MARK_DEBUG="true" *) 
 
reg  [5:0]            frame_cnt      = 1'b0;  
reg  [7:0]            e_txd_d0       = 1'b0;
reg                   e_tx_en_d0     = 1'b0;
reg  [7:0]            e_txd_d1       = 1'b0;
reg                   e_tx_en_d1     = 1'b0;
reg  [7:0]            e_txd_d2       = 1'b0;
reg                   e_tx_en_d2     = 1'b0;
reg  [7:0]            e_txd_d3       = 1'b0;
reg                   e_tx_en_d3     = 1'b0;
reg                   crc_reset      = 1'b0;
reg                   crc_en         = 1'b0;
wire [31:0]           crc;
reg                   FIFO_rd        = 1'b0;
wire [nETH*8-1:0]     data_FIFO_out;
reg                   FIFO_wr        = 1'b0;
reg  [3:0]            data_cnt       = 1'b0;
reg  [nETH*8-1:0]     outbuff        = 1'b0;
reg  [7:0]            sequence_cnt   = 1'b1;   //1'b1
wire                  FIFO_empty; 
reg                   bussy_d0       = 1'b0;



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
always @(posedge e_clk) begin
    e_txd_d2      <= e_txd_d1; 
    e_tx_en_d2    <= e_tx_en_d1; 
    e_txd_d3      <= e_txd_d2; 
    e_tx_en_d3    <= e_tx_en_d2; 
    e_txd         <= e_txd_d3;      //this is new, two more FF-delays to ease routing. 
    e_tx_en       <= e_tx_en_d3; 
    if (ErrorReset) sequence_cnt <= 1'b1;
    else if (frame_cnt==6'd0)  begin            //Idle   
        bussy_d0    <= 1'b0;
        e_txd_d0    <= 8'h00;
        e_txd_d1    <= 8'h00;
        e_tx_en_d1  <= 1'b0;
        e_tx_en_d0  <= 1'b0;
        crc_en      <= 1'b0;
        crc_reset   <= 1'b1;
        if(~FIFO_empty) begin 
          frame_cnt <= 6'd1;    
        end       
      end else if (frame_cnt < 6'd8)  begin //Preamble
        bussy_d0   <= 1'b1;
        frame_cnt  <= frame_cnt + 1'b1;
        crc_reset  <= 1'b0;
        e_tx_en_d0 <= 1'b1;
        e_txd_d0   <= 8'h55;
        e_txd_d1   <= e_txd_d0; 
        e_tx_en_d1 <= e_tx_en_d0;
        if (frame_cnt == 6'd5) FIFO_rd <= 1'b1;
        if (frame_cnt == 6'd6) FIFO_rd <= 1'b0;   
        if (frame_cnt == 6'd7) outbuff <= data_FIFO_out;      
      end else if (frame_cnt == 6'd8)  begin //Preamble
        frame_cnt  <= frame_cnt + 1'b1;
        e_txd_d0   <= 8'hd5;    
        e_txd_d1   <= e_txd_d0; 
      end else if (frame_cnt <= 6'd8+nETH) begin //send data
        frame_cnt  <= frame_cnt + 1'b1;
        e_txd_d0   <= outbuff[nETH*8-1:nETH*8-8];
        outbuff    <= {outbuff[nETH*8-9:0],8'b0}; 
        e_txd_d1   <= e_txd_d0; 
        crc_en     <= 1'b1;
        if (frame_cnt == 6'd7+nETH) FIFO_rd <= 1'b0;
      end else if (frame_cnt == 6'd9+nETH) begin
        e_txd_d0     <= sequence_cnt;
        e_txd_d1     <= e_txd_d0;
        sequence_cnt <= sequence_cnt+1'b1;
        frame_cnt  <= frame_cnt + 1'b1;
      end else if (frame_cnt == 6'd10+nETH) begin  
        crc_en     <= 1'b0;
        frame_cnt  <= frame_cnt + 1'b1;
        e_txd_d1   <= e_txd_d0;   
      end else if (frame_cnt == 6'd11+nETH) begin  //send crc
        frame_cnt  <= frame_cnt + 1'b1;
        e_txd_d1   <= {~crc[24], ~crc[25], ~crc[26], ~crc[27], ~crc[28], ~crc[29], ~crc[30], ~crc[31]} ;
      end else if (frame_cnt == 6'd12+nETH) begin  
        frame_cnt  <= frame_cnt + 1'b1;
        e_txd_d1   <= {~crc[16], ~crc[17], ~crc[18], ~crc[19], ~crc[20], ~crc[21], ~crc[22], ~crc[23]} ;
      end else if (frame_cnt == 6'd13+nETH) begin
        frame_cnt  <= frame_cnt + 1'b1;
        e_txd_d1   <= {~crc[8], ~crc[9], ~crc[10], ~crc[11], ~crc[12], ~crc[13], ~crc[14], ~crc[15]}   ;
      end else if (frame_cnt == 6'd14+nETH) begin 
        frame_cnt  <= frame_cnt + 1'b1; 
        e_txd_d1   <= {~crc[0], ~crc[1], ~crc[2], ~crc[3], ~crc[4], ~crc[5], ~crc[6], ~crc[7]}   ;
      end else if (frame_cnt < 6'd26+nETH) begin //interpacket gap
        e_tx_en_d1 <= 1'b0;
        frame_cnt  <= frame_cnt + 1'b1;
        e_txd_d1   <= 8'h00;
        e_txd_d0   <= 8'h00;
      end else      
        frame_cnt  <= 1'b0;         
    end
    

crc32 crc3 
(
.Clk      (e_clk), 
.Reset    (crc_reset),
.Data_in  (e_txd_d0),
.Enable   (crc_en), 
.Crc      (crc)
); 


ClkTransferStat #(.Width (1))  ClkTransferStat  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (bussy_d0),
    .sigOut  (bussy_d2)
); 

//extend busy signal of ETH_tx by extra 400ns to account for latency of ETH chip 
reg  [5:0] DelayBussy_cnt=1'b0;
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
