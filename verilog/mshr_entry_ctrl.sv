/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename  :  mshr_entry_ctrl.sv                                  //
//                                                                     //
//  Description :  Finite State Machine to derive the state of a       //
//                 MSHR entry.                                         // 
//                                                                     //
/////////////////////////////////////////////////////////////////////////

module mshr_entry_ctrl #(
    parameter   C_MSHR_ENTRY_NUM    =   `MSHR_ENTRY_NUM             ,
    parameter   C_CACHE_BLOCK_SIZE  =   `CACHE_BLOCK_SIZE           ,
    localparam  C_MSHR_IDX_WIDTH    =   $clog2(C_MSHR_ENTRY_NUM)
) (
    input   logic                                                       clk_i               ,   //  Clock
    input   logic                                                       rst_i               ,   //  Reset
    //  MSHR contents
    input   logic   [C_MSHR_IDX_WIDTH-1:0]                              mshr_entry_idx_i    ,   //  MSHR entry index
    output  MSHR_ENTRY                                                  mshr_entry_o        ,   //  MSHR entry contents
    //  Processor Interface
    input   logic                                                       proc_grant_i        ,
    input   MEM_IN                                                      proc_i              ,   //  Interface input
    output  MEM_OUT                                                     mshr_proc_o         ,   //  Interface output
    //  cache_mem Interface
    input   logic                                                       cache_mem_grant_i   ,   //  Indicate if the cache_mem Interface is granted to this entry
    input   CACHE_MEM_CTRL                                              cache_mem_ctrl_i    ,   //  Interface input
    output  CACHE_CTRL_MEM                                              mshr_cache_mem_o    ,   //  Interface output
    //  Memory Interface
    input   logic                                                       memory_grant_i      ,   //  Indicate if the Memory Interface is granted to this entry
    input   MEM_OUT                                                     mem_i               ,   //  Interface input
    output  MEM_IN                                                      mshr_memory_o       ,
    //  Hit Detection        
    input   logic                                                       mshr_hit_i          ,   //  Indicate if there is a match of miss address in MSHR
    input   logic   [C_MSHR_IDX_WIDTH-1:0]                              mshr_hit_idx_i      ,   //  The index of entry whose req_addr matches the address from processor
    input   logic                                                       evict_hit_i         ,   //  Indicate if there is a match of evict address in MSHR
    input   logic   [C_MSHR_IDX_WIDTH-1:0]                              evict_hit_idx_i     ,   //  The index of entry whose evict_addr matches the address from processor
    //  Dispatch
    input   logic                                                       dp_sel_i            ,   //  Dispatch select
    //  Complete
    output  logic                                                       mshr_cp_flag_o      ,   //  Complete flag of this entry
    output  logic   [C_CACHE_BLOCK_SIZE*8-1:0]                          mshr_cp_data_o      ,   //  The data written to cache_mem by this entry
    input   logic   [C_MSHR_ENTRY_NUM-1:0]                              cp_flag_i           ,   //  Complete flags of each entries
    input   logic   [C_MSHR_ENTRY_NUM-1:0][C_CACHE_BLOCK_SIZE*8-1:0]    cp_data_i               //  The data written to cache by each entry
);

// ====================================================================
// Local Parameters Declarations Start
// ====================================================================

// ====================================================================
// Local Parameters Declarations End
// ====================================================================

// ====================================================================
// Signal Declarations Start
// ====================================================================
    MSHR_ENTRY                          mshr_entry          ;
    MSHR_ENTRY                          next_mshr_entry     ;

    logic                               next_mshr_cp_flag   ;
    logic   [C_CACHE_BLOCK_SIZE*8-1:0]  next_mshr_cp_data   ;
// ====================================================================
// Signal Declarations End
// ====================================================================

// ====================================================================
// RTL Logic Start
// ====================================================================

// --------------------------------------------------------------------
// FSM and MSHR entry update
// --------------------------------------------------------------------
    always_ff @(posedge clk_i) begin
        if (rst_i) begin
            mshr_entry.state        <=  `SD ST_IDLE     ;
            mshr_entry.cmd          <=  `SD BUS_NONE    ;
            mshr_entry.req_addr     <=  `SD 'b0         ;
            mshr_entry.req_data     <=  `SD 'b0         ;
            mshr_entry.req_size     <=  `SD BYTE        ;
            mshr_entry.evict_addr   <=  `SD 'b0         ;
            mshr_entry.evict_data   <=  `SD 'b0         ;
            mshr_entry.evict_dirty  <=  `SD 1'b0        ;
            mshr_entry.link_idx     <=  `SD 'd0         ;
            mshr_entry.mem_tag      <=  `SD 'd0         ;
            mshr_cp_flag_o          <=  `SD 1'b0        ;
        end else begin
            mshr_entry              <=  `SD next_mshr_entry     ;
            mshr_cp_flag_o          <=  `SD next_mshr_cp_flag   ;
            mshr_cp_data_o          <=  `SD next_mshr_cp_data   ;
        end
    end

    always_comb begin
        next_mshr_entry.state       =   mshr_entry.state        ;
        next_mshr_entry.cmd         =   mshr_entry.cmd          ;
        next_mshr_entry.req_addr    =   mshr_entry.req_addr     ;
        next_mshr_entry.req_data    =   mshr_entry.req_data     ;
        next_mshr_entry.req_size    =   mshr_entry.req_size     ;
        next_mshr_entry.evict_addr  =   mshr_entry.evict_addr   ;
        next_mshr_entry.evict_data  =   mshr_entry.evict_data   ;
        next_mshr_entry.evict_dirty =   mshr_entry.evict_dirty  ;
        next_mshr_entry.link_idx    =   mshr_entry.link_idx     ;
        next_mshr_entry.linked      =   mshr_entry.linked       ;
        next_mshr_entry.mem_tag     =   mshr_entry.mem_tag      ;
        next_mshr_cp_flag           =   mshr_cp_flag_o          ;
        next_mshr_cp_data           =   mshr_cp_data_o          ;
        case (mshr_entry.state)
            ST_IDLE     :   begin
                // IF   there is a valid transaction on Processor Interface
                // AND  the cache_mem Interface is granted to this entry
                // AND  it is a miss
                // AND  the entry is selected to hold the new miss
                if ((proc_i.command != BUS_NONE) && (cache_mem_grant_i == 1'b1)
                && (cache_mem_ctrl_i.req_hit == 1'b0) && (dp_sel_i == 1'b1)) begin
                    // IF   there is an older transaction to the same addreess
                    // ->   Wait for the completion of older miss to the same address
                    if (mshr_hit_i && cp_flag_i[mshr_hit_idx_i] == 1'b0) begin
                        next_mshr_entry.state       =   ST_WAIT_DEPEND  ;
                        next_mshr_entry.link_idx    =   mshr_hit_idx_i  ;
                    // IF   there is an older transaction that is in the middle of evicting the data block
                    // ->   Wait for the completion of write-back to memory
                    end else if (evict_hit_i && cp_flag_i[evict_hit_idx_i] == 1'b0) begin
                        next_mshr_entry.state       =   ST_WAIT_EVICT   ;
                        next_mshr_entry.link_idx    =   evict_hit_idx_i ;
                    // ELSE
                    // ->   Read from Memory
                    end else begin
                        next_mshr_entry.state       =   ST_RD_MEM   ;
                        next_mshr_entry.link_idx    =   'd0         ;
                    end
                    next_mshr_entry.cmd         =   proc_i.command  ;
                    next_mshr_entry.req_addr    =   proc_i.addr     ;
                    next_mshr_entry.req_size    =   proc_i.size     ;
                    next_mshr_entry.req_data    =   proc_i.data     ;
                end
                next_mshr_cp_flag   =   1'b0    ;
                next_mshr_cp_data   =   'b0     ;
            end
            ST_WAIT_DEPEND  :   begin
                // IF   the older transaction that the entry is linked to completed
                // ->   Update the cache data
                if (cp_flag_i[mshr_entry.link_idx] == 1'b1) begin
                    next_mshr_entry.state       =   ST_UPDATE   ;
                    next_mshr_entry.link_idx    =   'd0         ;
                    next_mshr_entry.req_data    =   cp_data_i[mshr_entry.link_idx];
                    if (mshr_entry.cmd == BUS_STORE) begin
                        case (mshr_entry.req_size)
                            BYTE    :   next_mshr_entry.req_data[mshr_entry.req_addr[2:0] +:  8]    =   mshr_entry.req_data[ 7:0]   ;
                            HALF    :   next_mshr_entry.req_data[mshr_entry.req_addr[2:0] +: 16]    =   mshr_entry.req_data[15:0]   ;
                            WORD    :   next_mshr_entry.req_data[mshr_entry.req_addr[2:0] +: 32]    =   mshr_entry.req_data[31:0]   ;
                            DOUBLE  :   next_mshr_entry.req_data                                    =   mshr_entry.req_data         ;
                            default :   next_mshr_entry.req_data                                    =   mshr_entry.req_data         ;
                        endcase
                    end
                end
            end
            ST_WAIT_EVICT   : begin
                // IF   the older transaction that evicts the cache block completed
                // ->   Read from Memory
                if (cp_flag_i[mshr_entry.link_idx] == 1'b1) begin
                    next_mshr_entry.state       =   ST_RD_MEM   ;
                    next_mshr_entry.link_idx    =   'd0         ;
                end
            end
            ST_RD_MEM   :   begin
                // IF   the read transaction is confirmed by Memory Interface
                // ->   Wait for the data to return from Memory
                if ((memory_grant_i == 1'b1) && (mem_i.response != 'd0)) begin
                    next_mshr_entry.state       =   ST_WAIT_MEM     ;
                    next_mshr_entry.mem_tag     =   mem_i.response  ;
                end
            end
            ST_WAIT_MEM :   begin
                // IF   the data is returned from the Memory
                // ->   Update the cache data
                if (mem_i.tag == mshr_entry.mem_tag) begin
                    next_mshr_entry.state   =   ST_UPDATE   ;
                    next_mshr_entry.req_data    =   mem_i.data  ;
                    if (mshr_entry.cmd == BUS_STORE) begin
                        case (mshr_entry.req_size)
                            BYTE    :   next_mshr_entry.req_data[mshr_entry.req_addr[2:0] +:  8]    =   mshr_entry.req_data[ 7:0]   ;
                            HALF    :   next_mshr_entry.req_data[mshr_entry.req_addr[2:0] +: 16]    =   mshr_entry.req_data[15:0]   ;
                            WORD    :   next_mshr_entry.req_data[mshr_entry.req_addr[2:0] +: 32]    =   mshr_entry.req_data[31:0]   ;
                            DOUBLE  :   next_mshr_entry.req_data                                    =   mshr_entry.req_data         ;
                            default :   next_mshr_entry.req_data                                    =   mshr_entry.req_data         ;
                        endcase
                    end
                end
            end
            ST_UPDATE   :   begin
                // IF   the req interface is granted to this entry
                if (cache_mem_grant_i == 1'b1) begin
                    // IF   it is a load miss
                    // ->   Output data to processor
                    if (mshr_entry.cmd == BUS_LOAD) begin
                        next_mshr_entry.state       =   ST_OUTPUT;
                        next_mshr_entry.evict_addr  =   cache_mem_ctrl_i.evict_addr ;
                        next_mshr_entry.evict_data  =   cache_mem_ctrl_i.evict_data ;
                        next_mshr_entry.evict_dirty =   cache_mem_ctrl_i.evict_dirty;
                    // IF   a dirty block is evicted
                    // ->   Write back the evicted block
                    end else if (cache_mem_ctrl_i.evict_dirty == 1'b1) begin
                        next_mshr_entry.state       =   ST_EVICT;
                        next_mshr_entry.evict_addr  =   cache_mem_ctrl_i.evict_addr ;
                        next_mshr_entry.evict_data  =   cache_mem_ctrl_i.evict_data ;
                        next_mshr_entry.evict_dirty =   cache_mem_ctrl_i.evict_dirty;
                    // ELSE
                    // ->   Miss Handling Completed
                    end else begin
                        next_mshr_entry.state       =   ST_IDLE             ;
                        next_mshr_entry.cmd         =   BUS_NONE            ;
                        next_mshr_entry.req_addr    =   'b0                 ;
                        next_mshr_entry.req_data    =   'b0                 ;
                        next_mshr_entry.req_size    =   BYTE                ;
                        next_mshr_entry.evict_addr  =   'b0                 ;
                        next_mshr_entry.evict_data  =   'b0                 ;
                        next_mshr_entry.evict_dirty =   1'b0                ;
                        next_mshr_entry.link_idx    =   'd0                 ;
                        next_mshr_entry.mem_tag     =   'd0                 ;
                        next_mshr_cp_flag           =   1'b1                ;
                        next_mshr_cp_data           =   mshr_entry.req_data ;
                    end
                end
            end
            ST_OUTPUT   :   begin
                // IF   the Processor Interface is granted to this entry
                if (proc_grant_i == 1'b1) begin
                    // IF   the evicted block is dirty
                    // ->   Write back the evicted block
                    if (mshr_entry.evict_dirty == 1'b1) begin
                        next_mshr_entry.state       =   ST_EVICT;
                    // ELSE
                    // ->   Miss Handling Completed
                    end else begin
                        next_mshr_entry.state       =   ST_IDLE             ;
                        next_mshr_entry.cmd         =   BUS_NONE            ;
                        next_mshr_entry.req_addr    =   'b0                 ;
                        next_mshr_entry.req_data    =   'b0                 ;
                        next_mshr_entry.req_size    =   BYTE                ;
                        next_mshr_entry.evict_addr  =   'b0                 ;
                        next_mshr_entry.evict_data  =   'b0                 ;
                        next_mshr_entry.evict_dirty =   1'b0                ;
                        next_mshr_entry.link_idx    =   'd0                 ;
                        next_mshr_entry.mem_tag     =   'd0                 ;
                        next_mshr_cp_flag           =   1'b1                ;
                        next_mshr_cp_data           =   mshr_entry.req_data ;
                    end
                end
            end
            ST_EVICT    :   begin
                // IF   the write back transaction to Memory is confirmed
                // ->   Miss Handling Completed
                if ((memory_grant_i == 1'b1) && (mem_i.response != 'd0)) begin
                    next_mshr_entry.state       =   ST_IDLE             ;
                    next_mshr_entry.cmd         =   BUS_NONE            ;
                    next_mshr_entry.req_addr    =   'b0                 ;
                    next_mshr_entry.req_data    =   'b0                 ;
                    next_mshr_entry.req_size    =   BYTE                ;
                    next_mshr_entry.evict_addr  =   'b0                 ;
                    next_mshr_entry.evict_data  =   'b0                 ;
                    next_mshr_entry.evict_dirty =   1'b0                ;
                    next_mshr_entry.link_idx    =   'd0                 ;
                    next_mshr_entry.mem_tag     =   'd0                 ;
                    next_mshr_cp_flag           =   1'b1                ;
                    next_mshr_cp_data           =   mshr_entry.req_data ;
                end
            end
            default     :   begin
                next_mshr_entry.state       =   ST_IDLE     ;
                next_mshr_entry.cmd         =   BUS_NONE    ;
                next_mshr_entry.req_addr    =   'b0         ;
                next_mshr_entry.req_data    =   'b0         ;
                next_mshr_entry.req_size    =   BYTE        ;
                next_mshr_entry.evict_addr  =   'b0         ;
                next_mshr_entry.evict_data  =   'b0         ;
                next_mshr_entry.evict_dirty =   1'b0        ;
                next_mshr_entry.link_idx    =   'd0         ;
                next_mshr_entry.mem_tag     =   'd0         ;
                next_mshr_cp_flag           =   1'b0        ;
                next_mshr_cp_data           =   'd0         ;
            end
        endcase

        if (next_mshr_entry.state == ST_IDLE) begin
            next_mshr_entry.linked  =   1'b0;
        end else if ((mshr_hit_i == 1'b1) && (mshr_hit_idx_i == mshr_entry_idx_i)) begin
            next_mshr_entry.linked  =   1'b1;
        end
    end

// --------------------------------------------------------------------
// Processor Interface
// --------------------------------------------------------------------
    always_comb begin
        mshr_proc_o.response    =   'd0 ;
        mshr_proc_o.data        =   'b0 ;
        mshr_proc_o.tag         =   'd0 ;
        case (mshr_entry.state)
            ST_IDLE     :   begin
                // IF   the processor request is allocated to this entry
                if ((proc_i.command != BUS_NONE) && (cache_mem_grant_i == 1'b1)
                && (dp_sel_i == 1'b1)) begin
                    mshr_proc_o.response    =   mshr_entry_idx_i;
                    mshr_proc_o.data        =   cache_mem_ctrl_i.req_data_out;
                    if (cache_mem_ctrl_i.req_hit == 1'b1) begin
                        mshr_proc_o.tag     =   mshr_entry_idx_i;
                    end else begin
                        mshr_proc_o.tag     =   'd0;
                    end
                end
            end
            ST_OUTPUT   :   begin
                if (mshr_entry.cmd == BUS_LOAD) begin
                    mshr_proc_o.response    =   'd0             ;
                    mshr_proc_o.data        =   mshr_entry.data ;
                    mshr_proc_o.tag         =   mshr_entry_idx_i;
                end
            end
        endcase
    end

// --------------------------------------------------------------------
// cache_mem Interface
// --------------------------------------------------------------------
    always_comb begin
        cache_ctrl_mem_o.req_cmd        =   REQ_NONE;
        cache_ctrl_mem_o.req_addr       =   'b0     ;
        cache_ctrl_mem_o.req_data_in    =   'b0     ;
        case (mshr_entry.state)
            ST_IDLE:    begin
                // IF   the processor request is allocated to this entry
                if (dp_sel_i == 1'b1) begin
                    case (proc_i.command)
                        BUS_LOAD    :   begin
                            cache_ctrl_mem_o.req_cmd        =   REQ_LOAD                ;
                            cache_ctrl_mem_o.req_addr       =   proc_i.addr             ;
                            cache_ctrl_mem_o.req_data_in    =   cache_mem_ctrl_i.data   ;
                        end
                        BUS_STORE   :   begin
                            cache_ctrl_mem_o.req_cmd        =   REQ_STORE               ;
                            cache_ctrl_mem_o.req_addr       =   proc_i.addr             ;
                            cache_ctrl_mem_o.req_data_in    =   cache_mem_ctrl_i.data   ;
                            case (proc_i.size)
                                BYTE    :   cache_ctrl_mem_o.req_data_in[proc_i.addr[2:0] +:  8]    =   proc_i.data[ 7:0]   ;
                                HALF    :   cache_ctrl_mem_o.req_data_in[proc_i.addr[2:0] +: 16]    =   proc_i.data[15:0]   ;
                                WORD    :   cache_ctrl_mem_o.req_data_in[proc_i.addr[2:0] +: 32]    =   proc_i.data[31:0]   ;
                                DOUBLE  :   cache_ctrl_mem_o.req_data_in                            =   proc_i.data         ;
                            endcase
                        end    
                    endcase
                end
            end
            ST_UPDATE:  begin
                cache_ctrl_mem_o.req_cmd        =   REQ_MISS        ;
                cache_ctrl_mem_o.req_addr       =   proc_i.addr     ;
                cache_ctrl_mem_o.req_data_in    =   mshr_entry.data ;
            end
        endcase
    end

// --------------------------------------------------------------------
// Memory Interface
// --------------------------------------------------------------------
    always_comb begin
        mshr_memory_o.addr      =   {mshr_entry.req_addr[C_XLEN-1:C_CACHE_OFFSET_WIDTH], {C_CACHE_OFFSET_WIDTH{1'b0}}};
        mshr_memory_o.data      =   mshr_entry.data ;
        mshr_memory_o.size      =   DOUBLE          ;
        mshr_memory_o.command   =   BUS_NONE        ;
        case (mshr_entry.state)
            ST_RD_MEM   :   begin
                mshr_memory_o.addr      =   {mshr_entry.req_addr[C_XLEN-1:C_CACHE_OFFSET_WIDTH], {C_CACHE_OFFSET_WIDTH{1'b0}}};
                mshr_memory_o.command   =   BUS_LOAD;
            end
            ST_EVICT    :   begin
                mshr_memory_o.addr      =   {mshr_entry.evict_addr[C_XLEN-1:C_CACHE_OFFSET_WIDTH], {C_CACHE_OFFSET_WIDTH{1'b0}}};
                mshr_memory_o.command   =   BUS_STORE;
            end
        endcase
    end

// ====================================================================
// RTL Logic End
// ====================================================================


endmodule
