`timescale 1ns / 1ps

//- use ETH3 and ETH4 as 1Gb link to the nodes up and down. 
//- protocol: 7*8'h55, 8'hd5, data (nETH Byte), sequence_cnt (1byte), crc (4 byte),frame gap (min 1byte, but 12byte on the sending side)
//- complementary to ETH_tx
//- condition to start read sequence: proeprly delayed rising slope of e_rx_dv (with e_rx_dv still on to supress single spikes), or 8'hd5 
//  after rising slope of e_rx_dv (with e_rx_dv still on) together with data 8'h55. This accounts for bit errors in 8'hd5 or when number of preamble<7 in case of clock synchronisation   
//- received data are buffered at the end of sequence and are valid for at least another sequence 
//
//output:  
//data_valid      data valid
//data_recv       received data
//error           crc or sequence_cnt error


module ETH_rx
#(
parameter nETH  =  5'd28    //length of a data line
)
(
  input                   ErrorReset,
  input                   e_clk  ,   
  input                   IOclk,
  input                   e_rx_dv,
  input  [7:0]            e_rxd, 
  input                   e_rx_er,
  output reg [nETH*8-1:0] data_recv,
  output reg              data_valid,
  output [2:0]            error,
  output                  bussy
);
        
// (* MARK_DEBUG="true" *)
reg               e_rx_er_d0       = 1'b0;
reg               e_rx_er_d1       = 1'b0;    
reg               e_rx_er_d2       = 1'b0;
reg               e_rx_er_d3       = 1'b0;    
reg               e_rx_dv_d0       = 1'b0;
reg               e_rx_dv_d1       = 1'b0;
reg               e_rx_dv_d2       = 1'b0;
reg               e_rx_dv_d3       = 1'b0;
reg  [1:0]        e_rx_dv_slope    = 1'b0;
reg  [7:0]        e_rxd_d0         = 1'b0;  
reg  [7:0]        e_rxd_d1         = 1'b0;  
reg  [7:0]        e_rxd_d2         = 1'b0;  
reg  [7:0]        e_rxd_d3         = 1'b0; 
reg  [5:0]        frame_cnt        = 1'b0;   
reg               crc_reset        = 1'b0;
reg               crc_en           = 1'b0;
wire [31:0]       crc;
reg  [3:0]        wait_cnt         = 1'b0;
reg  [nETH*8-1:0] data_recv_d0     = 1'b0;
reg  [7:0]        sequence_cnt_old = 1'b0;
reg  [7:0]        sequence_cnt_d0  = 1'b0;
reg               bussy_d0         = 1'b0;
reg               data_valid_d0    = 1'b0;
wire              data_valid_d1;
reg               crc_error_d0     = 1'b0;
reg               seq_error_d0     = 1'b0;
reg               seq_error_d1     = 1'b0;

    
always @(posedge e_clk) begin
  e_rxd_d0    <= e_rxd;
  e_rx_dv_d0  <= e_rx_dv;
  e_rx_er_d0  <= e_rx_er;
  e_rxd_d1    <= e_rxd_d0;        
  e_rx_dv_d1  <= e_rx_dv_d0; 
  e_rx_er_d1  <= e_rx_er_d0;     
  e_rxd_d2    <= e_rxd_d1;        
  e_rx_dv_d2  <= e_rx_dv_d1; 
  e_rx_er_d2  <= e_rx_er_d1;    
  e_rxd_d3    <= e_rxd_d2;        
  e_rx_dv_d3  <= e_rx_dv_d2; 
  e_rx_er_d3  <= e_rx_er_d2;     
  e_rx_dv_slope <= {e_rx_dv_slope[0],e_rx_dv_d3}; 
  if (ErrorReset) sequence_cnt_old <= 1'b0;
  else if (frame_cnt==6'd0)  begin            //Idle   
    bussy_d0        <= 1'b0;
    crc_error_d0    <= 1'b0;
    seq_error_d0    <= 1'b0;
    crc_en          <= 1'b0;
    crc_reset       <= 1'b1;
    data_valid_d0   <= 1'b0;
    wait_cnt        <= 1'b0;
    if((e_rx_dv_slope==2'b01) && e_rx_dv_d3 && (e_rxd_d3==8'h55))  frame_cnt <= 1'b1;   
  end else if (frame_cnt==6'd1)  begin
    bussy_d0  <= 1'b1;
    crc_reset <= 1'b0;   
    wait_cnt  <= wait_cnt+1'b1;
 //   if (wait_cnt>4'd10) begin      
 //     frame_cnt <= 6'd14+nETH;  //error
 //     error_d0  <= 1'b1;
 //   end   
 //   if(e_rxd_d3==8'h55) frame_cnt <= 6'd2;   
 // end else if (frame_cnt==6'd2)  begin
 //   wait_cnt <= wait_cnt+1'b1;
 //   if (wait_cnt>4'd10) begin      
 //     frame_cnt <= 6'd14+nETH;  //error
 //     error_d0  <= 1'b1;
 //   end
 // if(e_rxd_d3==8'hd5) begin   
    if(((e_rxd_d3==8'hd5)&&e_rx_dv_d3)||wait_cnt==4'd5) begin
       frame_cnt    <= 6'd9;
       crc_en       <= 1'b1;
    end
  end else if (frame_cnt <= 6'd8+nETH) begin //receive data
    frame_cnt     <= frame_cnt + 1'b1; 
    data_recv_d0  <= {data_recv_d0[nETH*8-9:0],e_rxd_d3}; 
  end else if (frame_cnt == 6'd9+nETH) begin  //check sequence_cnt
    if (e_rxd_d3 != sequence_cnt_old + 1'b1) seq_error_d0 <= 1'b1;
    sequence_cnt_d0     <= e_rxd_d3;
    crc_en              <= 1'b0;
    frame_cnt <= frame_cnt + 1'b1;
  end else if (frame_cnt == 6'd10+nETH) begin  //check crc
    if (e_rxd_d3 != {~crc[24], ~crc[25], ~crc[26], ~crc[27], ~crc[28], ~crc[29], ~crc[30], ~crc[31]}) begin
       crc_error_d0   <= 1'b1;
       frame_cnt  <= 6'd14+nETH;
    end else frame_cnt  <= frame_cnt + 1'b1;  
  end else if (frame_cnt == 6'd11+nETH) begin  
    if (e_rxd_d3 != {~crc[16], ~crc[17], ~crc[18], ~crc[19], ~crc[20], ~crc[21], ~crc[22], ~crc[23]}) begin
      crc_error_d0   <= 1'b1;
      frame_cnt  <= 6'd14+nETH;
    end else frame_cnt  <= frame_cnt + 1'b1;  
  end else if (frame_cnt == 6'd12+nETH) begin
    if (e_rxd_d3 != {~crc[8], ~crc[9], ~crc[10], ~crc[11], ~crc[12], ~crc[13], ~crc[14], ~crc[15]}) begin  
      crc_error_d0   <= 1'b1;
      frame_cnt  <= 6'd14+nETH;
    end else frame_cnt  <= frame_cnt + 1'b1;
  end else if (frame_cnt == 6'd13+nETH) begin 
    frame_cnt  <= frame_cnt + 1'b1; 
    if (e_rxd_d3 != {~crc[0], ~crc[1], ~crc[2], ~crc[3], ~crc[4], ~crc[5], ~crc[6], ~crc[7]}) crc_error_d0 <= 1'b1;  
  end else begin
    frame_cnt  <= 1'b0;   //done
    if(crc_error_d0) begin                         
      sequence_cnt_old <= sequence_cnt_old + 1'b1;   //received data, but wrong; avoid that next error is a sequence error
    end else begin
      seq_error_d1     <= seq_error_d0;            
      sequence_cnt_old <= sequence_cnt_d0;
      data_valid_d0    <= 1'b1;                    //valid data, but might be sequence error
    end   
  end  
end  

crc32 crc4 
(
.Clk      (e_clk), 
.Reset    (crc_reset),
.Data_in  (e_rxd_d3),
.Enable   (crc_en), 
.Crc      (crc)
); 

//transfer between clock domains
ClkTransfer #(.extend (2)) ClkTransfer1  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (data_valid_d0),
    .sigOut  (data_valid_d1)
); 

ClkTransfer #(.extend (2)) ClkTransfer2  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (crc_error_d0),
    .sigOut  (crc_error)
); 

ClkTransfer #(.extend (2)) ClkTransfer3  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (seq_error_d1),
    .sigOut  (seq_error)
); 

ClkTransfer #(.extend (2)) ClkTransfer4  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (e_rx_er_d3),
    .sigOut  (e_rx_er_d4)
); 
assign error={e_rx_er_d4,seq_error,crc_error};

ClkTransferStat  #(.Width (1)) ClkTransferStat  
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (bussy_d0),
    .sigOut  (bussy_d2)
); 
assign bussy = bussy_d2;

    
always @(posedge IOclk) begin 
  if (data_valid_d1) data_recv <= data_recv_d0;
  data_valid    <= data_valid_d1;
end
    
    
endmodule
