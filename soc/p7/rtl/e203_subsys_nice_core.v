// SPDX-License-Identifier: MIT
// Replacement for the public ZIP's demo NICE core. Do not compile both copies.
// This wrapper targets the observed E203_XLEN=E203_ADDR_SIZE=32 configuration.
`include "e203_defines.v"
`ifndef KWT_MEM_BASE
`define KWT_MEM_BASE 32'h00000000
`endif
`ifndef KWT_MEM_BYTES
`define KWT_MEM_BYTES 32'h00000000
`endif
`ifndef KWT_W_BANK_AW
`define KWT_W_BANK_AW 7
`endif
`ifndef KWT_PACK_LOW_FIRST
`define KWT_PACK_LOW_FIRST 1
`endif
`ifdef E203_HAS_NICE
module e203_subsys_nice_core (
  input nice_clk, nice_rst_n,
  output nice_active, nice_mem_holdup,
  input nice_req_valid, output nice_req_ready,
  input [`E203_XLEN-1:0] nice_req_inst, nice_req_rs1, nice_req_rs2,
  output nice_rsp_valid, input nice_rsp_ready,
  output [`E203_XLEN-1:0] nice_rsp_rdat, output nice_rsp_err,
  output nice_icb_cmd_valid, input nice_icb_cmd_ready,
  output [`E203_ADDR_SIZE-1:0] nice_icb_cmd_addr,
  output nice_icb_cmd_read,
  output [`E203_XLEN-1:0] nice_icb_cmd_wdata,
  output [1:0] nice_icb_cmd_size,
  input nice_icb_rsp_valid, output nice_icb_rsp_ready,
  input [`E203_XLEN-1:0] nice_icb_rsp_rdata, input nice_icb_rsp_err
);
  generate if (`E203_XLEN!=32 || `E203_ADDR_SIZE!=32) begin: unsupported
    KWT_REQUIRES_32_BIT_E203 deliberate_elaboration_error();
  end endgenerate
  kwt_nice_core #(.MEM_BASE(`KWT_MEM_BASE),.MEM_BYTES(`KWT_MEM_BYTES),
    .W_BANK_AW(`KWT_W_BANK_AW),.PACK_LOW_FIRST(`KWT_PACK_LOW_FIRST)) u_kwt (
    .nice_clk(nice_clk),.nice_rst_n(nice_rst_n),
    .nice_active(nice_active),.nice_mem_holdup(nice_mem_holdup),
    .nice_req_valid(nice_req_valid),.nice_req_ready(nice_req_ready),
    .nice_req_inst(nice_req_inst),.nice_req_rs1(nice_req_rs1),.nice_req_rs2(nice_req_rs2),
    .nice_rsp_valid(nice_rsp_valid),.nice_rsp_ready(nice_rsp_ready),
    .nice_rsp_rdat(nice_rsp_rdat),.nice_rsp_err(nice_rsp_err),
    .nice_icb_cmd_valid(nice_icb_cmd_valid),.nice_icb_cmd_ready(nice_icb_cmd_ready),
    .nice_icb_cmd_addr(nice_icb_cmd_addr),.nice_icb_cmd_read(nice_icb_cmd_read),
    .nice_icb_cmd_wdata(nice_icb_cmd_wdata),.nice_icb_cmd_size(nice_icb_cmd_size),
    .nice_icb_rsp_valid(nice_icb_rsp_valid),.nice_icb_rsp_ready(nice_icb_rsp_ready),
    .nice_icb_rsp_rdata(nice_icb_rsp_rdata),.nice_icb_rsp_err(nice_icb_rsp_err)
  );
endmodule
`endif
