/*
 * core_datapath.sv
 *
 * Authors: David and Sarah Harris
 * Updated By: Sat Garcia
 *
 * Module that implements datapath component of MIPS core.
 */

module core_datapath(input  logic   clk, reset,
                input  logic        mem_to_reg_w, pc_src_d,
                input  logic        alu_src_x, reg_dest_x,
                input  logic        reg_write_w, jump_d,
                input  logic [2:0]  alu_ctrl_x,
                output logic        equal_d,
                output logic [31:0] pc,
                input  logic [31:0] instr_f,
                output logic [31:0] instr_d,
                output logic [31:0] alu_out_m, dmem_write_data_m,
                input  logic [31:0] dmem_read_data_m);

	// Fetch (F) stage signals
	logic [31:0] pc_plus_4_f, pc_next_br_f, pc_next_f;

	// Decode (D) stage signals
	logic [31:0] pc_plus_4_d, pc_branch_d, sign_imm_d, srca_d, dmem_write_data_d, sign_imm_shifted_d;
	logic [4:0] instr_rt_reg_d, instr_rd_reg_d;
	
	// Execute (X) stage signals
	logic [31:0] dmem_write_data_x, srca_x, srcb_x, sign_imm_x, sign_imm_shifted_x, pc_branch_x, alu_out_x;
	logic [4:0] rt_x, rd_x, instr_rt_reg_x, instr_rd_reg_x, write_reg_x;

	// Memory (M) stage signals
	logic [31:0] pc_branch_m;
	logic [4:0] write_reg_m;
	
	// Writeback (W) stage signals
	logic [31:0] alu_out_w, dmem_read_data_w, result_w;
	logic [4:0] write_reg_w;


	// Fetch (F) stage datapath components
	
	flopr #(32) pcreg(.clk, .reset, .d(pc_next_f), .q(pc));

	adder #(32) pcadd1(.a(pc), .b(32'b100), .y(pc_plus_4_f));

	mux2 #(32) pcbrmux(.d0(pc_plus_4_f), .d1(pc_branch_d), .sel(pc_src_d),
						  .y(pc_next_br_f));

	mux2 #(32) pcmux(.d0(pc_next_br_f), 
					  .d1({pc_plus_4_d[31:28], instr_d[25:0], 2'b00}), 
					  .sel(jump_d), .y(pc_next_f));


	// Fetch-to-Decode Inter-stage Registers
	flopr #(32) pc_plus_4_reg_f_d(.clk, .reset, .d(pc_plus_4_f), .q(pc_plus_4_d));
	flopr #(32) instr_reg_f_d(.clk, .reset, .d(instr_f), .q(instr_d));

	// Decode (D) stage datapath components 
	
	// Note: reg file also used WB
	regfile #(32,32) rf(.clk(~clk), .we3(reg_write_w & ~reset), 
						.ra1(instr_d[25:21]), .ra2(instr_d[20:16]),
						.rd1(srca_d), .rd2(dmem_write_data_d),
						.wa3(write_reg_w), .wd3(result_w)
					);

	signext se(.a(instr_d[15:0]), .y(sign_imm_d));

	shiftleft2 #(32) immsh(.a(sign_imm_d), .y(sign_imm_shifted_d));

	adder #(32) pcadd2(.a(pc_plus_4_d), .b(sign_imm_shifted_d), .y(pc_branch_d));

	assign equal_d = (srca_d == dmem_write_data_d);	

	// Decode-to-Execute Inter-stage Registers
	flopr #(32) dmem_write_data_reg_d_x(.clk, .reset, .d(dmem_write_data_d), .q(dmem_write_data_x));
	flopr #(32) srca_reg_d_x(.clk, .reset, .d(srca_d), .q(srca_x));
	flopr #(32) sign_imm_reg_d_x(.clk, .reset, .d(sign_imm_d), .q(sign_imm_x));
	flopr #(5) instr_rt_reg_d_x(.clk, .reset, .d(instr_d[20:16]), .q(rt_x)); 
	flopr #(5) instr_rd_reg_d_x(.clk, .reset, .d(instr_d[15:11]), .q(rd_x)); 


	// Execute (X) stage datapath components
	mux2 #(5) wrmux(.d0(rt_x), .d1(rd_x), .sel(reg_dest_x), 
					.y(write_reg_x));

	// selects if alu's 2nd input is immediate or register
	mux2 #(32) srcbmux(.d0(dmem_write_data_x), .d1(sign_imm_x),
						.sel(alu_src_x), .y(srcb_x));

	alu #(32) alu(.a(srca_x), .b(srcb_x), .f(alu_ctrl_x), .y(alu_out_x),
					.zero(zero_x), .carry(carry_x), .overflow(overflow_x));

	// Execute-to-Memory Inter-stage Registers
	flopr #(32) alu_out_reg_x_m(.clk, .reset, .d(alu_out_x), .q(alu_out_m));
	flopr #(32) dmem_write_data_reg_x_m(.clk, .reset, .d(dmem_write_data_x), .q(dmem_write_data_m));

	// "A foolish consistency is the hobgoblin of small minds..."
	flopr #(5) write_reg_reg_x_m(.clk, .reset, .d(write_reg_x), .q(write_reg_m));

	flopr #(32) pc_branch_reg_x_m(.clk, .reset, .d(pc_branch_x), .q(pc_branch_m));


	// Memory (M) stage datapath components
	
	// Memory-to-Writeback Inter-stage Registers
	flopr #(32) alu_out_reg_m_w(.clk, .reset, .d(alu_out_m), .q(alu_out_w));
	flopr #(32) dmem_read_data_reg_m_w(.clk, .reset, 
										.d(dmem_read_data_m), .q(dmem_read_data_w));
	flopr #(5) write_reg_reg_m_w(.clk, .reset, .d(write_reg_m), .q(write_reg_w));



	// Writeback (W) stage datapath components
	
	mux2 #(32) resmux(.d0(alu_out_w), .d1(dmem_read_data_w),
						 .sel(mem_to_reg_w), .y(result_w));

endmodule
