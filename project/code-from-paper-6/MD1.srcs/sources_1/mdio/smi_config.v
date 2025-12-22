`timescale 1 ns/1 ns
//Reads negotiated speed of MAC-PHY. In addition, if mode=1'b1, disables its EEE-option (i.e., energy saving) option
//by a sequence of commands, as described in RTL8211D(x)_EEE.pdf (page 5). Otherwise, sending data has a huge latency 
//of up to 20us. Done for ETH3 and ETH4 which are used for cross-linking, but not for ETH1 which is used for the 
//communication with the host PC. In addition, has signal that forces a ReNegotiation of the link in case connection is not good



module smi_config
#(
parameter REF_CLK = 50,         //reference clock frequency(MHz)
parameter MDC_CLK = 500         //mdc clock(KHz)
)
(
input                 clk,
output reg            e_reset,
//input                 restart,
output                mdc,         //mdc interface
inout                 mdio,        //mdio interface
output reg  [1:0]     speed,       //ethernet speed 00:10M 01:100M 10:1000M
output reg            link,        //ethernet link signal
input                 ReNegotiate, //ReNegotiate ETH-links 3 and 4
input                 mode         //0: read link and speed only, 1: disable EEE in addition    
);


reg                read_req   =1'b0 ;   //read smi request
wire [15:0]        read_data        ;   //read smi data
reg                write_req  =1'b0 ;   //write smi request
reg  [15:0]        write_data =1'b0 ;   //write smi data
reg  [4:0]         reg_addr=1'b0    ;
wire               done             ;	 //write or read finished
reg  [31:0]        timer            ;	 //wait counter 

reg [4:0]  state=1'b0;
reg [3:0]  write_cnt=1'b0;
reg        ReNegotiate_d0;

always @(posedge clk) begin
  if(ReNegotiate) ReNegotiate_d0<=1'b1;
  case(state)
    0: begin              //First run
       read_req  <= 1'b0;
       write_req <= 1'b0;
       write_cnt <= 1'b0;
       timer     <= 1'b0;
       e_reset   <= 1'b0;     //reset chip
       state     <= 5'd1;
    end
    1: begin
       timer <= timer + 1'b1;
       if (timer == 32'd10_000_000) begin   //reset active for 100 ms
         e_reset <= 1'b1; //release reset
         state   <= 5'd2;
         timer   <= 1'b0;
       end  
    end   
    2: begin
       timer <= timer + 1'b1;
       if (timer == 32'd10_000_000) begin   //wait another 100 ms
         timer   <= 1'b0;        
         if (mode) state <= 5'd6;  //disable EEE mode; for ETH3/4;
         else      state <= 5'd3;  //normal operation, i.e., request status every 0.5s
       end  
    end
    3: begin             //WAIT and repeat every 0.5
       write_cnt <= 1'b0;
       timer     <= timer + 1'b1 ;
       if (timer == 32'd50_000_000) begin
         timer   <= 1'b0;
         if(ReNegotiate_d0) begin
           ReNegotiate_d0  <= 1'b0;
           state           <= 5'd8;  //restart auto-negotiate
         end  
         else state        <= 5'd4;
       end  
    end 
    4: begin             //READ_REQ; speed and link
       reg_addr <= 5'd17;
       read_req <= 1'b1;
       timer    <= 1'b0;
       state    <= 5'd5;
    end  
    5: begin             //READ
       read_req <= 1'b0;
       if(done) begin
         link  <= read_data[10];
         speed <= read_data[15:14];
         if((read_data[10]==1'b1)&&(read_data[15:14]!=2'b10)) state <= 5'd0;            //reset chip again since it is not 1000MB/s
         else                                                 state <= 5'd3;            //loop and read every 1s
       end
    end 
    
//switch off power-saving options   
    6: begin             
       case (write_cnt)        
/*
         4'd0: begin                     //switch off "cable length power saving"
           reg_addr   <= 5'd31;
           write_data <= 16'h0003;
         end
         4'd1: begin
           reg_addr   <= 5'd25;
           write_data <= 16'h3246;
         end
         4'd2: begin
           reg_addr   <= 5'd16;
           write_data <= 16'ha87c;
         end
         4'd3: begin
           reg_addr   <= 5'd31;
           write_data <= 16'h0000;
         end
  */       
         4'd0: begin                     //switch of EEE
           reg_addr   <= 5'd31;
           write_data <= 16'h0005;
         end
         4'd1: begin
           reg_addr   <= 5'd5;
           write_data <= 16'h8b85;
         end
         4'd2: begin
           reg_addr   <= 5'd6;
           write_data <= 16'h0ae2;
         end
         4'd3: begin
           reg_addr   <= 5'd31;
           write_data <= 16'h0007;
         end
         4'd4: begin
           reg_addr   <= 5'd30;
           write_data <= 16'h0020;
         end
         4'd5: begin
           reg_addr   <= 5'd21;
           write_data <= 16'h1008;
         end
         4'd6: begin
           reg_addr   <= 5'd31;
           write_data <= 16'h0000;
         end
         4'd7: begin
           reg_addr   <= 5'd13;
           write_data <= 16'h0007;
         end
         4'd8: begin
           reg_addr   <= 5'd14;
           write_data <= 16'h003c;
         end
         4'd9: begin
           reg_addr   <= 5'd13;
           write_data <= 16'h4007;
         end
         4'd10: begin
           reg_addr   <= 5'd14;
           write_data <= 16'h0000;
         end
         default: ;
       endcase  
       write_cnt  <= write_cnt+1'b1;
       write_req  <= 1'b1; 
       state      <= 5'd7;
    end       
    7: begin             //Write
       write_req <= 1'b0;
       if(done) begin
         if(write_cnt<=10) state <= 5'd6;      //is 14 with "cable length power saving" switched off
         else              state <= 5'd3;
       end    
    end 
    
    8: begin                               //restart auto-negotiate
       case (write_cnt)        
         4'd0: begin                     
           reg_addr   <= 5'd31;
           write_data <= 16'h0000;
         end
         4'd1: begin                     
           reg_addr   <= 5'd0;
           write_data <= 16'b0001001101000000;  //bit 9 starts auto-negotiate
         end
       endcase  
       write_cnt  <= write_cnt+1'b1;
       write_req  <= 1'b1; 
       state      <= 5'd9;
    end       
    9: begin             //Write
       write_req <= 1'b0;
       if(done) begin
         if(write_cnt<=1)  state <= 5'd8;      
         else              state <= 5'd10;
       end    
    end    
    10: begin
       timer     <= timer + 1'b1 ;
       if (timer == 32'd50_000_000) begin  //wait 0.5s; will be 1s in total
         timer   <= 1'b0;
         state   <= 5'd3;
       end  
    end    
    default: state <= 5'd0;
  endcase
end    

smi_read_write 
      #(
        .REF_CLK(REF_CLK),
        .MDC_CLK(MDC_CLK)
	   )
	   smi_inst
       (
        .clk              (clk         ),
        .rst_n            (1'b1        ),
        .mdc              (mdc         ),
        .mdio             (mdio        ),         
        .phy_addr         (5'b00001    ),
        .reg_addr         (reg_addr    ),	
        .write_req        (write_req   ),
        .write_data       (write_data  ),	 
        .read_req         (read_req    ),
        .read_data        (read_data   ),
        .done             (done        )
       );

 
endmodule
