
/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename  :  PRF.sv                                              //
//                                                                     //
//  Description :  PRF MODULE of the pipeline;                         // 
//                                                                     //
/////////////////////////////////////////////////////////////////////////

`ifndef __PRF_V__
`define __PRF_V__

`timescale 1ns/100ps

module PRF # ( 
    parameter   C_DP_NUM            =   `DP_NUM         ,
    parameter   C_THREAD_NUM        =   `THREAD_NUM     ,
    parameter   C_ROB_ENTRY_NUM     =   `ROB_ENTRY_NUM  ,
    parameter   C_ARCH_REG_NUM      =   `ARCH_REG_NUM   ,
    parameter   C_PHY_REG_NUM       =   `PHY_REG_NUM    
) (
    input   logic                          clk_i                ,   // Clock
    input   logic                          rst_i                ,   // Reset
    input   RS_PRF                         rs_prf_i             ,  
    //per_channel 
    output  PRF_RS                         prf_rs_o             ,
    //per_channel
    input   BC_PRF                         bc_prf_i              
    //per_channel
);

// ====================================================================
// Local Parameters Declarations Start
// ====================================================================

    logic  [`DP_NUM-1:0][`DP_NUM-1:0]         hit1     ;
    logic  [`DP_NUM-1:0][`DP_NUM-1:0]         hit2     ;
    logic  [31:0] [`XLEN-1:0]                 registers;   
    // 32, 64-bit Registers   
    logic  [`XLEN-1:0]                        rd1_reg  ;
    logic  [`XLEN-1:0]                        rd2_reg  ;

    assign  rd1_reg = registers[rs_prf_i.rd_addr1];
    assign  rd2_reg = registers[rs_prf_i.rd_addr2];

// ====================================================================
// Local Parameters Declarations End
// ====================================================================


// ====================================================================
// RTL Logic Start
// ====================================================================
// --------------------------------------------------------------------
// hit detection
// --------------------------------------------------------------------

//   rd_idx: loop over read ports
//   wr_idx: loop over write ports

    for (rd_idx = 0 ; rd_idx < C_DP_NUM; rd_idx++) begin
        for (wr_idx = 0 ; wr_idx < C_DP_NUM; wr_idx++) begin
            if(bc_prf_i[wr_idx].wr_addr == rs_prf_i[rd_idx].rd_addr1) begin
                hit1[rd_idx][wr_idx] = 1;
            end//if hit1
            if(bc_prf_i[wr_idx].wr_addr == rs_prf_i[rd_idx].rd_addr2) begin
                hit2[rd_idx][wr_idx] = 1;
            end//if hit2
        end//for wr_idx
    end//for rd_idx

  // --------------------------------------------------------------------
  // Read port A
  // --------------------------------------------------------------------

    always_comb begin
        for (rd_idx = 0 ; rd_idx < C_DP_NUM; rd_idx++) begin
            if (rs_prf_i[rd_idx].rd_addr1 == `ZERO_REG)begin
                prf_rs_o[rd_idx].data_out1 = 0;
            end else if (bc_prf_i[rd_idx].wr_en && (|hit1[rd_idx])) begin //There's match
                for (wr_idx = 0; wr_idx < C_DP_NUM; wr_idx++) begin
                    if (hit1[rd_idx][wr_idx]) begin
                        prf_rs_o[rd_idx].data_out1 = bc_prf_i[wr_idx].data_in;  // internal forwarding
                    end
                end
            end else begin
                prf_rs_o[rd_idx].data_out1 = rd1_reg;
            end
        end//for
    end//comb

  // --------------------------------------------------------------------
  // Read port B
  // --------------------------------------------------------------------

    always_comb begin
        for (rd_idx = 0 ; rd_idx < C_DP_NUM; rd_idx++) begin
            if (rs_prf_i[rd_idx].rd_addr2 == `ZERO_REG)begin
                prf_rs_o[rd_idx].data_out2 = 0;
            end else if (bc_prf_i[rd_idx].wr_en && (|hit2[rd_idx])) begin //There's match
                for (wr_idx = 0; wr_idx < C_DP_NUM; wr_idx++) begin
                    if (hit2[rd_idx][wr_idx]) begin
                        prf_rs_o[rd_idx].data_out2 = bc_prf_i[wr_idx].data_in;  // internal forwarding
                    end
                end
            end else begin
                prf_rs_o[rd_idx].data_out2 = rd2_reg;
            end
        end//for
    end//comb

  // --------------------------------------------------------------------
  // Write port
  // --------------------------------------------------------------------

    always_ff @(posedge clk_i) begin
        for (idx = 0 ; idx < C_DP_NUM; idx++) begin
            if (rst_i) begin
            registers[bc_prf_i[idx].wr_addr] <= `SD 'b0;
            end if (bc_prf_i[idx].wr_en) begin
            registers[bc_prf_i[idx].wr_addr] <= `SD bc_prf_i[idx].data_in;
            end//if
        end//for
    end//ff

// ====================================================================
// RTL Logic End
// ====================================================================

endmodule // regfile
`endif //__PRF__
