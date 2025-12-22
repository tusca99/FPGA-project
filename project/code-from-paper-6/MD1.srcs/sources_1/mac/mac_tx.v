`timescale 1ns / 1ps

//trasnmitting part of a minimal Mac socket that does both UDP annd ARP. Used ALINX ETH-example as starting point, 
//but has been changed and simplified significantly. Complementary to mac_rx.v

module mac_tx(
                   input                e_clk  ,    
                   
                   output reg           e_tx_en,
                   output reg [7:0]     e_txd, 
 //                  input                speed,                    
                    
                   input  [47:0]        local_mac_addr ,       
                   input  [31:0]        local_ip_addr,
                   input  [15:0]        local_udp_port,
                   input  [47:0]        remote_mac_addr ,       
                   input  [31:0]        remote_ip_addr,
                   input  [15:0]        remote_udp_port,
                   
                   input                arp_req,
                   input  [47:0]        arp_remote_mac_addr,   
                   input  [31:0]        arp_remote_ip_addr,
                  
                   input                udp_tx_req,
                   output  reg          udp_send_end,
                   input  [7:0]         udp_send_data,  
                   output  reg          udp_ram_data_req, 
                   input  [15:0]        udp_send_data_length  
    );
   
   

wire [15:0] udp_fill_data_length= (udp_send_data_length<16'd18) ?  16'd18 : udp_send_data_length; //fill with zeros in case too short     
wire [15:0] udp_total_data_length=udp_send_data_length+16'd8;                                     //including header; written into header
wire [15:0] ip_data_length=udp_send_data_length+16'd28;                                           //including header; written into header
reg  [15:0] identify_code=1'b0;
wire [31:0] crc;
wire [15:0] checksum;   
reg  [3:0]  FrameState = 1'b0;   
reg  [5:0]  frame_cnt  = 1'b0;  
reg  [10:0] wait_cnt   = 1'b0;
reg  [7:0]  e_txd_d0   = 1'b0;
reg  [7:0]  e_txd_d1   = 1'b0;
reg         e_tx_en_d0 = 1'b0;
reg         e_tx_en_d1 = 1'b0;
reg  [7:0]  e_txd_d2   = 1'b0;
reg         e_tx_en_d2 = 1'b0;
reg  [7:0]  e_txd_d3   = 1'b0;
reg         e_tx_en_d3 = 1'b0;
reg         udp_tx_req2= 1'b0;
reg         crc_reset  = 1'b1;

always @(posedge e_clk) begin
        e_txd_d2      <= e_txd_d1;         //FF delays to ease routing 
        e_tx_en_d2    <= e_tx_en_d1; 
        e_txd_d3      <= e_txd_d2; 
        e_tx_en_d3    <= e_tx_en_d2; 
        e_txd         <= e_txd_d3;      
        e_tx_en       <= e_tx_en_d3;     
        if (udp_tx_req) udp_tx_req2 <= 1'b1;  //keep in case arp is running
        case (FrameState)
          0: begin
               wait_cnt      <= 1'b0;
               udp_send_end  <= 1'b0;
               frame_cnt     <= 1'b0;
               e_tx_en_d1    <= 1'b0;
               e_tx_en_d0    <= 1'b0;
               crc_reset     <= 1'b1;
               if (udp_tx_req2)  FrameState <= 4'd1; //UDP has priority
               else if (arp_req) FrameState <= 4'd5;
             end      
          1: begin
               crc_reset   <= 1'b0;
               udp_tx_req2 <= 1'b0;
               frame_cnt   <= frame_cnt+1'b1;
               e_txd_d1    <= e_txd_d0;
               e_tx_en_d1  <= e_tx_en_d0;
               case (frame_cnt)
                 6'd0   : begin
                            e_txd_d0   <= 8'h55;                   //preamble
                            e_tx_en_d0 <= 1'b1;
                          end           
                 6'd7   : e_txd_d0 <= 8'hd5;
                 6'd8   : e_txd_d0 <= remote_mac_addr[47:40];    //start Eithernet header
                 6'd9   : e_txd_d0 <= remote_mac_addr[39:32];
                 6'd10  : e_txd_d0 <= remote_mac_addr[31:24];
                 6'd11  : e_txd_d0 <= remote_mac_addr[23:16];
                 6'd12  : e_txd_d0 <= remote_mac_addr[15:8];
                 6'd13  : e_txd_d0 <= remote_mac_addr[7:0];
                 6'd14  : e_txd_d0 <= local_mac_addr[47:40];
                 6'd15  : e_txd_d0 <= local_mac_addr[39:32];
                 6'd16  : e_txd_d0 <= local_mac_addr[31:24];
                 6'd17  : e_txd_d0 <= local_mac_addr[23:16];
                 6'd18  : e_txd_d0 <= local_mac_addr[15:8];
                 6'd19  : e_txd_d0 <= local_mac_addr[7:0];
                 6'd20  : e_txd_d0 <= 8'h08;                      //IP protocol
                 6'd21  : e_txd_d0 <= 8'h00;                
                 6'd22  : e_txd_d0 <= 8'h45;                    //start IP header; IP versionn and header length
                 6'd23  : e_txd_d0 <= 8'h00;
                 6'd24  : e_txd_d0 <= ip_data_length[15:8];       
                 6'd25  : e_txd_d0 <= ip_data_length[7:0];
                 6'd26  : e_txd_d0 <= identify_code[15:8];
                 6'd27  : e_txd_d0 <= identify_code[7:0];
                 6'd28  : e_txd_d0 <= 8'h40;
                 6'd29  : e_txd_d0 <= 8'h00;
                 6'd30  : e_txd_d0 <= 8'h80;                      //TTL
                 6'd31  : e_txd_d0 <= 8'h11;                      //UDP protocol
                 6'd32  : e_txd_d0 <= checksum[15:8];
                 6'd33  : e_txd_d0 <= checksum[7:0];
                 6'd34  : e_txd_d0 <= local_ip_addr[31:24];
                 6'd35  : e_txd_d0 <= local_ip_addr[23:16];
                 6'd36  : e_txd_d0 <= local_ip_addr[15:8];
                 6'd37  : e_txd_d0 <= local_ip_addr[7:0];
                 6'd38  : e_txd_d0 <= remote_ip_addr[31:24];
                 6'd39  : e_txd_d0 <= remote_ip_addr[23:16];
                 6'd40  : e_txd_d0 <= remote_ip_addr[15:8];
                 6'd41  : e_txd_d0 <= remote_ip_addr[7:0];
                 6'd42  : e_txd_d0 <= local_udp_port[15:8] ;          //start UDP-header
                 6'd43  : e_txd_d0 <= local_udp_port[7:0] ;
                 6'd44  : e_txd_d0 <= remote_udp_port[15:8] ;
                 6'd45  : e_txd_d0 <= remote_udp_port[7:0] ;
                 6'd46  : e_txd_d0 <= udp_total_data_length[15:8];      
                 6'd47  : begin
                            e_txd_d0 <= udp_total_data_length[7:0];
                            udp_ram_data_req <= 1'b1;                //needs to be sent 2 cycles in advance
                          end  
                 6'd48  : begin
                            e_txd_d0 <= 8'h00;                      //UDP checksum, but is not mandatory
                            udp_ram_data_req <= 1'b0;
                          end  
                 6'd49  : begin 
                            e_txd_d0 <= 8'h00;
                            FrameState <= 4'd2;
                          end  
                 default: ;
               endcase
             end
          2: begin                                            //send UDP data
               wait_cnt <= wait_cnt+1'b1;
               e_txd_d0 <= (wait_cnt<udp_send_data_length) ? udp_send_data : 1'b0;
               e_txd_d1 <= e_txd_d0;
               if (wait_cnt==udp_fill_data_length - 1'b1) begin
                 FrameState <= 4'd3;
               end 
             end      
          3: begin                                         //send overall checksum; 
               wait_cnt<=1'b0;
               frame_cnt <= frame_cnt+1'b1;
               case (frame_cnt) //delay by one for crc calculation
                  6'd50: e_txd_d1 <= e_txd_d0;
                  6'd51: e_txd_d1 <= {~crc[24], ~crc[25], ~crc[26], ~crc[27], ~crc[28], ~crc[29], ~crc[30], ~crc[31]} ;
                  6'd52: e_txd_d1 <= {~crc[16], ~crc[17], ~crc[18], ~crc[19], ~crc[20], ~crc[21], ~crc[22], ~crc[23]} ;
                  6'd53: e_txd_d1 <= {~crc[8], ~crc[9], ~crc[10], ~crc[11], ~crc[12], ~crc[13], ~crc[14], ~crc[15]}   ;
                  6'd54: begin
                           e_txd_d1 <= {~crc[0], ~crc[1], ~crc[2], ~crc[3], ~crc[4], ~crc[5], ~crc[6], ~crc[7]}   ;
                           FrameState <= 4'd4; 
                         end  
                  default: ;       
               endcase 
             end
          4: begin                                        //frame gap; 
               e_tx_en_d1 <= 1'b0;    
               e_txd_d1   <= 8'h00;
               e_txd_d0   <= 8'h00;  
               wait_cnt   <= wait_cnt+1'b1;
               if (wait_cnt==11'd12) begin
                 FrameState    <= 4'd0;                
                 identify_code <= identify_code+1'b1;
                 udp_send_end  <= 1'b1;
               end   
             end
//***********************************ARP response**********************
          5: begin
               crc_reset   <= 1'b0;
               frame_cnt <= frame_cnt+1'b1;
               e_txd_d1  <= e_txd_d0;
               e_tx_en_d1<= e_tx_en_d0;
               case (frame_cnt)              
                 6'd0   : begin
                            e_txd_d0   <= 8'h55;                   //preamble
                            e_tx_en_d0 <= 1'b1;
                          end           
                 6'd7   : e_txd_d0 <= 8'hd5;
                 6'd8   : e_txd_d0 <= arp_remote_mac_addr[47:40];    
                 6'd9   : e_txd_d0 <= arp_remote_mac_addr[39:32];
                 6'd10  : e_txd_d0 <= arp_remote_mac_addr[31:24];
                 6'd11  : e_txd_d0 <= arp_remote_mac_addr[23:16];
                 6'd12  : e_txd_d0 <= arp_remote_mac_addr[15:8];
                 6'd13  : e_txd_d0 <= arp_remote_mac_addr[7:0];
                 6'd14  : e_txd_d0 <= local_mac_addr[47:40];
                 6'd15  : e_txd_d0 <= local_mac_addr[39:32];
                 6'd16  : e_txd_d0 <= local_mac_addr[31:24];
                 6'd17  : e_txd_d0 <= local_mac_addr[23:16];
                 6'd18  : e_txd_d0 <= local_mac_addr[15:8];
                 6'd19  : e_txd_d0 <= local_mac_addr[7:0];
                 6'd20  : e_txd_d0 <= 8'h08;                      //ARP protocol
                 6'd21  : e_txd_d0 <= 8'h06;      
                 6'd22  : e_txd_d0 <= 8'h00;  
                 6'd23  : e_txd_d0 <= 8'h01; 
                 6'd24  : e_txd_d0 <= 8'h08;  
                 6'd25  : e_txd_d0 <= 8'h00;
                 6'd26  : e_txd_d0 <= 8'h06;  
                 6'd27  : e_txd_d0 <= 8'h04;
                 6'd28  : e_txd_d0 <= 8'h00;  
                 6'd29  : e_txd_d0 <= 8'h02;                      //ARP response     
                 6'd30  : e_txd_d0 <= local_mac_addr[47:40];
                 6'd31  : e_txd_d0 <= local_mac_addr[39:32];
                 6'd32  : e_txd_d0 <= local_mac_addr[31:24];
                 6'd33  : e_txd_d0 <= local_mac_addr[23:16];
                 6'd34  : e_txd_d0 <= local_mac_addr[15:8];
                 6'd35  : e_txd_d0 <= local_mac_addr[7:0];
                 6'd36  : e_txd_d0 <= local_ip_addr[31:24];
                 6'd37  : e_txd_d0 <= local_ip_addr[23:16];
                 6'd38  : e_txd_d0 <= local_ip_addr[15:8];
                 6'd39  : e_txd_d0 <= local_ip_addr[7:0];
                 6'd40  : e_txd_d0 <= arp_remote_mac_addr[47:40];
                 6'd41  : e_txd_d0 <= arp_remote_mac_addr[39:32];
                 6'd42  : e_txd_d0 <= arp_remote_mac_addr[31:24];
                 6'd43  : e_txd_d0 <= arp_remote_mac_addr[23:16];
                 6'd44  : e_txd_d0 <= arp_remote_mac_addr[15:8];
                 6'd45  : e_txd_d0 <= arp_remote_mac_addr[7:0];
                 6'd46  : e_txd_d0 <= arp_remote_ip_addr[31:24];
                 6'd47  : e_txd_d0 <= arp_remote_ip_addr[23:16];
                 6'd48  : e_txd_d0 <= arp_remote_ip_addr[15:8];
                 6'd49  : begin
                            e_txd_d0 <= arp_remote_ip_addr[7:0];
                            FrameState    <= 4'd06;
                          end  
                 default: ;
               endcase            
          end
          6: begin                                            //fill for 46 bytes
               wait_cnt <= wait_cnt+1'b1;
               e_txd_d0 <= 1'b0;
               e_txd_d1 <= e_txd_d0;
               if (wait_cnt==11'd17) begin
                 FrameState <= 4'd7;
               end
             end      
          7: begin                                         //send overall checksum; 
               wait_cnt<=1'b0;
               frame_cnt <= frame_cnt+1'b1;
               case (frame_cnt)                         //delay by one for crc calculation
                  6'd51: e_txd_d1 <= {~crc[24], ~crc[25], ~crc[26], ~crc[27], ~crc[28], ~crc[29], ~crc[30], ~crc[31]} ;
                  6'd52: e_txd_d1 <= {~crc[16], ~crc[17], ~crc[18], ~crc[19], ~crc[20], ~crc[21], ~crc[22], ~crc[23]} ;
                  6'd53: e_txd_d1 <= {~crc[8], ~crc[9], ~crc[10], ~crc[11], ~crc[12], ~crc[13], ~crc[14], ~crc[15]}   ;
                  6'd54: begin
                           e_txd_d1 <= {~crc[0], ~crc[1], ~crc[2], ~crc[3], ~crc[4], ~crc[5], ~crc[6], ~crc[7]}   ;
                           FrameState <= 4'd8; 
                         end  
                  default: ;       
               endcase 
             end        
          8: begin                                        //frame gap; 
               e_tx_en_d1 <= 1'b0;    
               e_txd_d1   <= 8'h00;
               e_txd_d0   <= 8'h00;  
               wait_cnt   <= wait_cnt+1'b1;
               if (wait_cnt==11'd12) begin
                 FrameState    <= 4'd0;                
               end  
             end        
          default: ;
        endcase       
 end  

 
 //ip checksum generation
 wire ip_check_reset=(FrameState==4'd0);
 wire ip_check_en=(frame_cnt>=6'd1 && frame_cnt<=6'd10);
 IPcheck IPcheck1
(
.e_clk     (e_clk),
.reset     (ip_check_reset),
.enable    (ip_check_en),
.word1     (16'h4500),
.word2     (ip_data_length),
.word3     (identify_code),
.word4     (16'h4000),
.word5     (16'h8011),
.word6     (16'h0000), 
.word7     (local_ip_addr[31:16]),
.word8     (local_ip_addr[15:0]),
.word9     (remote_ip_addr[31:16]),
.word10    (remote_ip_addr[15:0]), 
.checksum  (checksum)
);
 

//overall checksum
wire crc_en=(frame_cnt>8)&&(frame_cnt<=50);
crc32 crc1 
(
.Clk      (e_clk), 
.Reset    (crc_reset),
.Data_in  (e_txd_d0),
.Enable   (crc_en), 
.Crc      (crc)
); 
 
endmodule
