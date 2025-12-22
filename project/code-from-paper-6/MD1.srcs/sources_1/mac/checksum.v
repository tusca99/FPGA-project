`timescale 1ns / 1ps

//checksum claculation. Taken over without change from the ALINX ETH-example

module IPcheck
(
input                    e_clk,
input                    reset,
input                    enable,
input      [15:0]        word1,
input      [15:0]        word2,
input      [15:0]        word3,
input      [15:0]        word4,
input      [15:0]        word5,
input      [15:0]        word6,
input      [15:0]        word7,
input      [15:0]        word8, 
input      [15:0]        word9,
input      [15:0]        word10, 
output reg [15:0]        checksum
);
    
reg  [16:0] checksum_tmp0 ;
reg  [16:0] checksum_tmp1 ;
reg  [16:0] checksum_tmp2 ;
reg  [16:0] checksum_tmp3 ;
reg  [16:0] checksum_tmp4 ;
reg  [17:0] checksum_tmp5 ;
reg  [17:0] checksum_tmp6 ;
reg  [18:0] checksum_tmp7 ;
reg  [19:0] checksum_tmp8 ;
reg  [19:0] check_out1 ;
reg  [19:0] check_out2 ;

//checksum function
function    [31:0]  checksum_adder
  (
    input       [31:0]  dataina,
    input       [31:0]  datainb
  );
  begin
    checksum_adder = dataina + datainb;
  end
endfunction

function    [31:0]  checksum_out
  (
    input       [31:0]  dataina
  );  
  begin
    checksum_out = dataina[15:0]+dataina[31:16];
  end  
endfunction


always @(posedge e_clk) begin
    if (reset)
      begin
        checksum_tmp0 <= 17'd0 ;
        checksum_tmp1 <= 17'd0 ;
        checksum_tmp2 <= 17'd0 ;
        checksum_tmp3 <= 17'd0 ;
        checksum_tmp4 <= 17'd0 ;
        checksum_tmp5 <= 18'd0 ;
        checksum_tmp6 <= 18'd0 ;
        checksum_tmp7 <= 19'd0 ;
        checksum_tmp8 <= 20'd0 ;
        check_out1    <= 20'd0 ;
        check_out2    <= 20'd0 ;
      end else if (enable) begin
        checksum_tmp0 <= checksum_adder(word1,word2);
        checksum_tmp1 <= checksum_adder(word3,word4);
        checksum_tmp2 <= checksum_adder(word5,word6) ;
        checksum_tmp3 <= checksum_adder(word7,word8) ;
        checksum_tmp4 <= checksum_adder(word9,word10) ;
        checksum_tmp5 <= checksum_adder(checksum_tmp0, checksum_tmp1) ;
        checksum_tmp6 <= checksum_adder(checksum_tmp2, checksum_tmp3) ;
        checksum_tmp7 <= checksum_adder(checksum_tmp5, checksum_tmp6) ;
        checksum_tmp8 <= checksum_adder(checksum_tmp4, checksum_tmp7) ;
        check_out1    <= checksum_out(checksum_tmp8) ;
        check_out2    <= checksum_out(check_out1) ;
        checksum      <= ~check_out2[15:0];
      end 
  end    
    
endmodule
