// if_stage.v (the actual hardware before the IF/ Pipeline
/////////////////////////////////////////////////////////////////////////
//                                                                     //
//  Modulename  :  if_stage.sv                                         //
//                                                                     //
//  Description :  Fetch stage of the pipeline;                        // 
//				   Contains all relevant modules that 				   //
//				   will be aid in the fetch process.			   	   //
//                 At a high level, reads a N-wide amount of		   // 
//				   instructions per thread and inserts into some	   //
//				   queue, computes next PC location, and			   //
// 		 	       sends them down the pipeline (To be processed	   //
// 		 	       in the dispatch / decode stage).					   //							  	   		   //
//                                                                     //
/////////////////////////////////////////////////////////////////////////

typedef struct packet {
	logic	[`XLEN-1:0] PC_reg;
	logic	[`XLEN-1:0] 
} THREAD;


`timescale 1ns/100ps


module if_stage # (
	parameter 	C_DP_NUM				= `DP_NUM			;
	parameter 	C_THREAD_NUM			= `THREAD_NUM		;
	parameter   C_
) (
	input	logic						clk_i				,		     // system clock
	input	logic						rst_i				,		     // System reset
	input	logic[C_THREAD_NUM-1:0]		pc_en 				,			 // only go to next instruction when true
	input   BR_MIS						br_mis				,			 // mis-predict  signal
	input [63:0]      Imem2proc_data,    // Data coming back from insruction memory. 

	output logic [`XLEN-1:0] proc2Imem_addr,  // Address sent to Intruction memory (to be feteched)
	output IF_ID_PACKET if_packet_out	 // Output data packet from IFgoing to ID (this is the instruction, PC, PC+1, and whether to care about if (if valid)
);
	
	// State of this ( section)
	logic [`XLEN-1:0] PC_reg;

	// Combintation logic wires (used to determine how the PC_reg will
	// change
	logic [`XLEN-1:0] 					PC_plus_4; // PC + 4
	logic [C_THREAD_NUM-1:0][`XLEN-1:0]   next_PC; // next_state
	logic 		      					PC_enable; // Do we update the PC?

	
	// The address requested to be fetched.
	always_comb
	begin
		for ( int n = 0; n < C_THREAD_NUM; n++ )
		begin
			
		end
	end
	assign proc2Imem_addr = { PC_reg[`XLEN-1:3], 3'b0 }; // Grab the 64-bits of the instruction (aka next two instructions (8 bytes aligned))

	// this mux is because the Imem gives us 64-bits, not 32-bits.
	assign if_packet_out.inst = PC_reg[ 2 ] ? Imem2proc_data[63:32] : Imem2proc_data[31:0]; // If one, grab the upper 4 bytes (the next instruction, o.w. the lower 4 bytes.

	// default next PC value
	assign PC_plus_4 = PC_reg + 4;


	// next PC is target_pc if there is a taken branch or
	// the next sequential PC (PC+4) if no branch
	// (halting is handled with the enable PC_enable)
	assign next_PC = ex_mem_take_branch ? ex_mem_target_pc : PC_plus_4;

	// The take-branch signal must override stalling (otherwise it may be
	// lost) ( Due to the instruction going forwards ex -> mem )
	assign PC_enable = pc_en | ex_mem_take_branch;


	// assign PC+4 down pipeline w/instruction
	assign if_packet_out.NPC = PC_plus_4;
	assign if_packet_out.PC = PC_reg;

	assign if_packet_out.valid = PC_enable; // This instruction isn't valid otherwise (esp if instruction is still being written to IF/ID registers)

	// This register holds the PC value
	// synopsys sync_set_reset "reset"
	always_ff @( posedge clock )
	begin
		if ( reset )
			PC_reg <= `SD 0; 	// inital PC value is 0
		else if ( PC_enable )
			PC_reg <= `SD next_PC;  // transition to next PC
		else
			PC_reg <= `SD PC_reg;
		end
endmodule
