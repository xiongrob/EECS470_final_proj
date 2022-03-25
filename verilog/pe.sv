/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename  :  pe.sv                                               //
//                                                                     //
//  Description :  pe                                                  // 
//                                                                     //
/////////////////////////////////////////////////////////////////////////

module pe #(
    parameter   C_IN_WIDTH  =   32                  ,
    parameter   C_OUT_WIDTH =   $clog2(C_IN_WIDTH)
)(
    input   logic   [C_IN_WIDTH-1:0]    bit_i   ,
    output  logic   [C_OUT_WIDTH-1:0]   enc_o   ,
    output  logic                       valid_o 
);

// ====================================================================
// RTL Logic Start
// ====================================================================

// --------------------------------------------------------------------
// Encoding
// --------------------------------------------------------------------
    always_comb begin
        enc_o   =   0;
        for (int i = C_IN_WIDTH-1; i >=0 ; i--) begin
            if (bit_i[i]) begin
                enc_o   =   i;
            end
        end
    end

// --------------------------------------------------------------------
// Valid
// --------------------------------------------------------------------
    assign  valid_o =   bit_i ? 1'b1 : 1'b0;

// ====================================================================
// RTL Logic End
// ====================================================================


endmodule