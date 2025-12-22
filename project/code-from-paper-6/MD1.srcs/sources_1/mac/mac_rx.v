`timescale 1ns / 1ps

//receiving part of a minimal Mac socket that does both UDP annd ARP. Used ALINX ETH-example as starting point, 
//but has been changed and simplified significantly. Complementary to mac_tx.v

module mac_rx
(
                   input                e_clk,
                   input                IOclk,
                   
                   input                e_rx_dv,
                   input      [7:0]     e_rxd,
//                   input                speed,
                  
                   input      [31:0]    local_ip_addr,
                   input      [15:0]    local_udp_port,
                   output reg [47:0]    remote_mac_addr,
                   output reg [31:0]    remote_ip_addr,
                   output reg [15:0]    remote_udp_port,

                   output reg           arp_req,
                   output reg  [47:0]   arp_remote_mac_addr,   
                   output reg  [31:0]   arp_remote_ip_addr,

                   output               udp_rec_data_valid,
                   output     [7:0]     udp_rec_ram_rdata ,      //udp ram read data
                   input      [10:0]    udp_rec_ram_read_addr    //udp ram read address
                   
);

     
reg  [47:0] remote_mac_addr_recv    =1'b0;   
reg  [31:0] remote_ip_addr_recv     =1'b0;
reg  [15:0] remote_port_recv        =1'b0; 
reg  [31:0] local_ip_addr_recv      =1'b0;
reg  [15:0] local_port_recv         =1'b0;  
reg  [15:0] protocol;
reg  [3:0]  FrameState              =1'b0;   
reg  [5:0]  frame_cnt               =1'b0;  
reg  [10:0] wait_cnt                =1'b0;
reg         udp_error               =1'b0;
reg         arp_error               =1'b0;
reg         udp_data_vld            =1'b0;
wire [31:0] crc;
reg         crc_en                  =1'b0;
reg         crc_reset               =1'b0;
reg         e_rx_dv_d0              =1'b0;
reg         e_rx_dv_d1              =1'b0;
reg  [1:0]  e_rx_dv_slope           =1'b0;
reg  [7:0]  e_rxd_d0                =1'b0;
reg  [7:0]  e_rxd_d1                =1'b0;
reg  [7:0]  e_rxd_d2                =1'b0;
reg  [3:0]  e_rxd_tmp               =1'b0;
reg         udp_rec_data_valid0     =1'b0;
reg  [15:0] ip_data_length          =1'b0; 
 
reg [15:0] udp_data_length;   
reg [15:0] udp_fill_data_length;



always @(posedge e_clk) begin 
    e_rxd_d0    <= e_rxd;           //FF delays to ease routing 
    e_rx_dv_d0  <= e_rx_dv;
    e_rxd_d1    <= e_rxd_d0;        
    e_rx_dv_d1  <= e_rx_dv_d0;       
    e_rxd_d2    <= e_rxd_d1;        
    e_rx_dv_slope <= {e_rx_dv_slope[0],e_rx_dv_d1}; 
    case (FrameState)
      0: begin
           frame_cnt          <= 1'b0; 
           wait_cnt           <= 1'b0;     
           udp_error          <= 1'b0;
           udp_data_vld       <= 1'b0;
           crc_en             <= 1'b0;
           udp_rec_data_valid0<= 1'b0;
           arp_req            <= 1'b0;
           arp_error          <= 1'b0;
           if(e_rx_dv_slope==2'b01) FrameState<=4'd1;
         end    
      1: begin
           wait_cnt <= wait_cnt+1'b1;
           if (wait_cnt>16'd10)  FrameState <= 4'd0;
           else if(e_rxd_d2==8'h55) begin                  
             FrameState <= 4'd2;
             crc_reset <= 1'b1;
           end    
      end
      2: begin
         wait_cnt <= wait_cnt+1'b1;
         if (wait_cnt>16'd10)  FrameState <= 4'd0;
         else begin
           crc_reset <= 1'b0;
           if(e_rxd_d2==8'hd5) begin
             FrameState   <= 4'd3;
             frame_cnt    <= 6'd8;
             crc_en       <= 1'b1;
           end
         end    
      end
      3: begin
        wait_cnt <= 1'b0;
        frame_cnt  <= frame_cnt + 1'b1;  
        case (frame_cnt)
          6'd14  : remote_mac_addr_recv[47:40] <= e_rxd_d2;
          6'd15  : remote_mac_addr_recv[39:32] <= e_rxd_d2;
          6'd16  : remote_mac_addr_recv[31:24] <= e_rxd_d2;
          6'd17  : remote_mac_addr_recv[23:16] <= e_rxd_d2;
          6'd18  : remote_mac_addr_recv[15:8]  <= e_rxd_d2;
          6'd19  : remote_mac_addr_recv[7:0]   <= e_rxd_d2;
          6'd20  : protocol[15:8] <= e_rxd_d2;                      
          6'd21  : begin
                     protocol[7:0] <= e_rxd_d2;
                     if      ({protocol[15:8],e_rxd_d2} == 16'h0800) FrameState <= 4'd4; 
                     else if ({protocol[15:8],e_rxd_d2} == 16'h0806) FrameState <= 4'd8; //forge to ARP
                          else                                       FrameState <= 4'd0;  
                   end  
          default: ;
        endcase                  
      end
      4: begin                                           //IP header starts here
        frame_cnt  <= frame_cnt + 1'b1;  
        case (frame_cnt)
          6'd24  : ip_data_length[15:8]       <= e_rxd_d2;       
          6'd25  : ip_data_length[7:0]        <= e_rxd_d2;
          6'd26  : udp_data_length            <= ip_data_length-16'd28;
          6'd27  : udp_fill_data_length       <= (udp_data_length<16'd18) ?  16'd18 : udp_data_length;
          6'd31  : if(e_rxd_d2!=8'h11) FrameState <= 4'd0;            //UDP protocol
          6'd34  : remote_ip_addr_recv[31:24] <= e_rxd_d2;
          6'd35  : remote_ip_addr_recv[23:16] <= e_rxd_d2;
          6'd36  : remote_ip_addr_recv[15:8]  <= e_rxd_d2;
          6'd37  : remote_ip_addr_recv[7:0]   <= e_rxd_d2;
          6'd38  : local_ip_addr_recv[31:24]  <= e_rxd_d2;
          6'd39  : local_ip_addr_recv[23:16]  <= e_rxd_d2;
          6'd40  : local_ip_addr_recv[15:8]   <= e_rxd_d2;
          6'd41  : begin
                     local_ip_addr_recv[7:0]  <= e_rxd_d2;
                     if({local_ip_addr_recv[31:8],e_rxd_d2}!=local_ip_addr) FrameState <= 4'd0;
                   end  
          6'd42  : remote_port_recv[15:8]     <= e_rxd_d2;          //start UDP-header
          6'd43  : remote_port_recv[7:0]      <= e_rxd_d2;         
          6'd44  : local_port_recv[15:8]      <= e_rxd_d2;
          6'd45  : begin                                         
                     local_port_recv[7:0]     <= e_rxd_d2;
                     if({local_port_recv[15:8],e_rxd_d2}!=local_udp_port) FrameState <= 4'd0;
                   end 
          6'd49  : begin
                     FrameState   <= 4'd5;
                     udp_data_vld <= 1'b1;
                   end  
          default: ;          
        endcase           
      end
      5: begin                                                   //read UDP data
           wait_cnt <= wait_cnt+1'b1;
           if (wait_cnt==udp_data_length - 1'b1) udp_data_vld <= 1'b0;
           if (wait_cnt==udp_fill_data_length - 1'b1) begin
             FrameState <= 4'd6;
             crc_en     <= 1'b0; 
           end
         end
      6: begin                                                         //read and compare CRC                                       
          frame_cnt  <= frame_cnt + 1'b1;  
          case (frame_cnt) 
            6'd50: if (e_rxd_d2!={~crc[24], ~crc[25], ~crc[26], ~crc[27], ~crc[28], ~crc[29], ~crc[30], ~crc[31]}) udp_error <= 1'b1;
            6'd51: if (e_rxd_d2!={~crc[16], ~crc[17], ~crc[18], ~crc[19], ~crc[20], ~crc[21], ~crc[22], ~crc[23]}) udp_error <= 1'b1;
            6'd52: if (e_rxd_d2!={~crc[8], ~crc[9], ~crc[10], ~crc[11], ~crc[12], ~crc[13], ~crc[14], ~crc[15]})   udp_error <= 1'b1;
            6'd53: begin
                     if (e_rxd_d2!={~crc[0], ~crc[1], ~crc[2], ~crc[3], ~crc[4], ~crc[5], ~crc[6], ~crc[7]})       udp_error <= 1'b1;
                     FrameState <= 4'd7; 
                   end  
            default: ;
          endcase               
         end
      7: begin
           if(~udp_error) begin
             remote_mac_addr    <= remote_mac_addr_recv;
             remote_ip_addr     <= remote_ip_addr_recv;
             remote_udp_port    <= remote_port_recv;
             udp_rec_data_valid0<= 1'b1;
           end  
           FrameState <= 4'd0;
         end 
//******************************ARP request*****************          
      8: begin                  //ARP request
           frame_cnt  <= frame_cnt + 1'b1;  
           case (frame_cnt)
             6'd29  : if (e_rxd_d2!=8'h01) FrameState <= 4'd0;  //has not been a arp request
             6'd30  : arp_remote_mac_addr[47:40] <= e_rxd_d2;
             6'd31  : arp_remote_mac_addr[39:32] <= e_rxd_d2;
             6'd32  : arp_remote_mac_addr[31:24] <= e_rxd_d2;
             6'd33  : arp_remote_mac_addr[23:16] <= e_rxd_d2;
             6'd34  : arp_remote_mac_addr[15:8]  <= e_rxd_d2;
             6'd35  : arp_remote_mac_addr[7:0]   <= e_rxd_d2;           
             6'd36  : arp_remote_ip_addr[31:24]  <= e_rxd_d2;
             6'd37  : arp_remote_ip_addr[23:16]  <= e_rxd_d2;
             6'd38  : arp_remote_ip_addr[15:8]   <= e_rxd_d2;
             6'd39  : arp_remote_ip_addr[7:0]    <= e_rxd_d2;
             6'd46  : local_ip_addr_recv[31:24]  <= e_rxd_d2;
             6'd47  : local_ip_addr_recv[23:16]  <= e_rxd_d2;
             6'd48  : local_ip_addr_recv[15:8]   <= e_rxd_d2;
             6'd49  : begin 
                       local_ip_addr_recv[7:0]  <= e_rxd_d2;
                       if({local_ip_addr_recv[31:8],e_rxd_d2}!=local_ip_addr) FrameState <= 4'd0;
                       else                                                   FrameState <= 4'd9;
                     end  
             default: ;
           endcase   
         end            
      9: begin                                                   
           wait_cnt <= wait_cnt+1'b1;    //fill for 46 bytes 
           if (wait_cnt==11'd17) begin
             FrameState <= 4'd10;
             crc_en     <= 1'b0; 
           end
         end
      10:begin                                                         //read and compare CRC                                       
           frame_cnt  <= frame_cnt + 1'b1;  
           case (frame_cnt) 
             6'd50: if (e_rxd_d2!={~crc[24], ~crc[25], ~crc[26], ~crc[27], ~crc[28], ~crc[29], ~crc[30], ~crc[31]}) arp_error <= 1'b1;
             6'd51: if (e_rxd_d2!={~crc[16], ~crc[17], ~crc[18], ~crc[19], ~crc[20], ~crc[21], ~crc[22], ~crc[23]}) arp_error <= 1'b1;
             6'd52: if (e_rxd_d2!={~crc[8], ~crc[9], ~crc[10], ~crc[11], ~crc[12], ~crc[13], ~crc[14], ~crc[15]})   arp_error <= 1'b1;
             6'd53: begin
                     if ((e_rxd_d2=={~crc[0], ~crc[1], ~crc[2], ~crc[3], ~crc[4], ~crc[5], ~crc[6], ~crc[7]})&&~arp_error) arp_req <= 1'b1;
                     FrameState <= 4'd0; 
                   end  
             default: ;
           endcase               
         end   
      default: ;            
      endcase   
end   

//**************************************************************************
//receiving memory; lattency 2
bram_8x2048 udp_receive_ram
(	
    .clka(e_clk),  
    .ena(1'b1),  
    .wea(udp_data_vld),      
    .addra(wait_cnt),  
    .dina(e_rxd_d2),    
    .clkb(IOclk),     
    .enb(1'b1),
    .addrb(udp_rec_ram_read_addr), 
    .doutb(udp_rec_ram_rdata)  
); 

//transfer signal to IOclk
ClkTransfer #(.extend (2)) ClkTransfer1
(
    .clkIn   (e_clk),
    .clkOut  (IOclk),
    .sigIn   (udp_rec_data_valid0),
    .sigOut  (udp_rec_data_valid)
);


//*************************************************************
//overall checksum
crc32 crc2
(
.Clk      (e_clk), 
.Reset    (crc_reset),
.Data_in  (e_rxd_d2),
.Enable   (crc_en), 
.Crc      (crc)
); 

endmodule
