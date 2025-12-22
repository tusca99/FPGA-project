`timescale 1ns / 1ps

//Defines a proper interface for the ETH's. Input data are delayed with respect to input clock by 2.4 ns, is 
//supposed to center-align them, but also to compensate for BUFG. Output clock is inverted to center-align it. Adapted from
//what the Vivado IP "SelectIO Interface Wizard" produces; major chnage is inversion of output clock

module ETH_IOport
(
  input        e_rx_clk_from_pins,        // Single ended clock input from PHY 
  output       e_tx_clk_to_pins,          //forwarded clk signal for PHY tx
  output       e_clk,                     //internal eth clk 
  input  [7:0] e_rxd_from_pins,
  output [7:0] e_rxd,
  input        e_rx_dv_from_pins,
  output       e_rx_dv,
  input  [7:0] e_txd,
  output [7:0] e_txd_to_pins,
  input        e_tx_en,
  output       e_tx_en_to_pins
);
    
  localparam InputDelay=31;             //average delay/tab is 78ps. works with 15=1.2ns and 31=2.4ns, but not with 0; 31 should be on the safe side
    
  wire         clk_fwd_out, clk_in_int;
  wire   [7:0] e_rxd_d0;
  wire   [7:0] e_rxd_d1;
  
 

//clock
    
 IBUF
    #(.IOSTANDARD ("LVCMOS33"))
   ibuf_clk_inst
     (.I          (e_rx_clk_from_pins),
      .O          (clk_in_int));
  
   BUFG clkout_buf_inst
    (.O (e_clk),
     .I (clk_in_int));

// clock forwarding logic
    ODDR
     #(.DDR_CLK_EDGE   ("SAME_EDGE"), //"OPPOSITE_EDGE" "SAME_EDGE"
       .INIT           (1'b0),
       .SRTYPE         ("ASYNC"))
     oddr_inst
      (.D1             (1'b0),         //reveals inverted, i.e., centered clock
       .D2             (1'b1),
       .C              (e_clk),
       .CE             (1'b1),
       .Q              (clk_fwd_out),
       .R              (1'b0),
       .S              (1'b0));

    OBUF
      #(.IOSTANDARD ("LVCMOS33"))
     obuf_clk_inst
       (.O          (e_tx_clk_to_pins),
        .I          (clk_fwd_out));    

   
// Instantiate a buffer for every bit of the data bus
  genvar i;
  generate for (i = 0; i < 8; i = i + 1) begin: pins
  
    IBUF
      #(.IOSTANDARD ("LVCMOS33"))
     ibuf_inst
       (.I          (e_rxd_from_pins[i]),
        .O          (e_rxd_d0[i]));

 IDELAYE2
       # (
         .CINVCTRL_SEL           ("FALSE"),             // TRUE, FALSE
         .DELAY_SRC              ("IDATAIN"),           // IDATAIN, DATAIN
         .HIGH_PERFORMANCE_MODE  ("FALSE"),             // TRUE, FALSE
         .IDELAY_TYPE            ("FIXED"),             // FIXED, VARIABLE, or VAR_LOADABLE
         .IDELAY_VALUE           (InputDelay),          // average delay/tab is 78ps,
         .REFCLK_FREQUENCY       (200.0),
         .PIPE_SEL               ("FALSE"),
         .SIGNAL_PATTERN         ("DATA"))                             // CLOCK, DATA
       idelaye1
           (
         .DATAOUT                (e_rxd_d1[i]),
         .DATAIN                 (1'b0),                               // Data from FPGA logic
         .C                      (1'b0),
         .CE                     (1'b0),
         .INC                    (1'b0),
         .IDATAIN                (e_rxd_d0[i]), // Driven by IOB
         .LD                     (1'b0),
         .REGRST                 (1'b0),
         .LDPIPEEN               (1'b0),
         .CNTVALUEIN             (5'b00000),
         .CNTVALUEOUT            (),
         .CINVCTRL               (1'b0)
         );


    (* IOB = "true" *)
    FDRE fdre_in_inst
      (.D              (e_rxd_d1[i]),     //delayed data
       .C              (e_clk),
       .CE             (1'b1),
       .R              (1'b0),
       .Q              (e_rxd[i])
      );
    
 wire e_txd_d0;
    (* IOB = "true" *)
    FDRE fdre_out_inst
      (.D              (e_txd[i]),
       .C              (e_clk),
       .CE             (1'b1),
       .R              (1'b0),
       .Q              (e_txd_d0)
      );
    
    OBUF
      #(.IOSTANDARD ("LVCMOS33"))
     obuf_inst
       (.O          (e_txd_to_pins[i]),
        .I          (e_txd_d0)
        );
  end
  endgenerate
  
//same for dv signals
   IBUF
      #(.IOSTANDARD ("LVCMOS33"))
     ibuf_inst2
       (.I          (e_rx_dv_from_pins),
        .O          (e_rx_dv_d0));
        
    IDELAYE2
       # (
         .CINVCTRL_SEL           ("FALSE"),             // TRUE, FALSE
         .DELAY_SRC              ("IDATAIN"),           // IDATAIN, DATAIN
         .HIGH_PERFORMANCE_MODE  ("FALSE"),             // TRUE, FALSE
         .IDELAY_TYPE            ("FIXED"),             // FIXED, VARIABLE, or VAR_LOADABLE
         .IDELAY_VALUE           (InputDelay),          //average delay/tab is 78ps
         .REFCLK_FREQUENCY       (200.0),
         .PIPE_SEL               ("FALSE"),
         .SIGNAL_PATTERN         ("DATA"))                             // CLOCK, DATA
       idelaye1
           (
         .DATAOUT                (e_rx_dv_d1),
         .DATAIN                 (1'b0),                              
         .C                      (1'b0),
         .CE                     (1'b0),
         .INC                    (1'b0),
         .IDATAIN                (e_rx_dv_d0), // Driven by IOB
         .LD                     (1'b0),
         .REGRST                 (1'b0),
         .LDPIPEEN               (1'b0),
         .CNTVALUEIN             (5'b00000),
         .CNTVALUEOUT            (),
         .CINVCTRL               (1'b0)
         );    

    (* IOB = "true" *)
    FDRE fdre_in_inst2
      (.D              (e_rx_dv_d1),
       .C              (e_clk),
       .CE             (1'b1),
       .R              (1'b0),
       .Q              (e_rx_dv)
      );
    
    (* IOB = "true" *)
    FDRE fdre_out_inst2
      (.D              (e_tx_en),
       .C              (e_clk),
       .CE             (1'b1),
       .R              (1'b0),
       .Q              (e_tx_en_d0)
      );
    
    OBUF
      #(.IOSTANDARD ("LVCMOS33"))
     obuf_inst2
       (.O          (e_tx_en_to_pins),
        .I          (e_tx_en_d0));
 
    
endmodule
