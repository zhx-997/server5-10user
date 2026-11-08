// SPDX-License-Identifier: MIT
// One transaction in flight. A response and the following command may turn
// over on the same edge. Both command and response skid storage are explicit.
module kwt43_icb_master (
  input wire clk,rst_n,req_valid,output wire req_ready,
  input wire [31:0] req_addr,req_wdata,input wire req_read,
  output wire ret_valid,input wire ret_ready,output wire [31:0] ret_rdata,
  output wire ret_err,cmd_valid,input wire cmd_ready,
  output wire [31:0] cmd_addr,cmd_wdata,output wire cmd_read,output wire [1:0] cmd_size,
  input wire rsp_valid,output wire rsp_ready,input wire [31:0] rsp_rdata,input wire rsp_err,
  output wire idle
);
  localparam EMPTY=0,SEND=1,WAIT_RSP=2,HOLD_RSP=3;
  reg [1:0] state;
  reg [31:0] addr_q,data_q,response_q;
  reg read_q,error_q;
  wire old_response=state==WAIT_RSP && rsp_valid;
  wire clear_old=(old_response || state==HOLD_RSP) && ret_ready;
  wire permit=rst_n && (state==EMPTY || (state==WAIT_RSP && clear_old));
  assign req_ready=permit;
  assign cmd_valid=rst_n && (state==SEND || (permit && req_valid));
  assign cmd_addr=state==SEND?addr_q:req_addr;
  assign cmd_wdata=state==SEND?data_q:req_wdata;
  assign cmd_read=state==SEND?read_q:req_read;
  assign cmd_size=2'b10;
  wire external_command=cmd_valid && cmd_ready;
  // 响应暂存寄存器空闲时提前接收响应，ready 不依赖命令握手。
  // 总线只对已接受的命令返回响应；已有暂存响应时停止接收下一项。
  assign rsp_ready=rst_n && state!=HOLD_RSP;
  wire incoming=rsp_valid && rsp_ready;
  assign ret_valid=rst_n && (state==HOLD_RSP || incoming);
  assign ret_rdata=state==HOLD_RSP?response_q:rsp_rdata;
  assign ret_err=state==HOLD_RSP?error_q:rsp_err;
  assign idle=state==EMPTY;
  wire accepted=req_valid && req_ready;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) state<=EMPTY;
    else if(accepted) begin
      if(!cmd_ready)state<=SEND;
      else if(state==EMPTY && incoming)state<=ret_ready?EMPTY:HOLD_RSP;
      else state<=WAIT_RSP;
    end else if(state==SEND) begin
      if(external_command)state<=incoming?(ret_ready?EMPTY:HOLD_RSP):WAIT_RSP;
    end else if(incoming)state<=ret_ready?EMPTY:HOLD_RSP;
    else if(state==HOLD_RSP && ret_ready)state<=EMPTY;
  end
  always @(posedge clk) begin
    if(accepted && !cmd_ready)begin addr_q<=req_addr;data_q<=req_wdata;read_q<=req_read;end
    if(incoming && !ret_ready)begin response_q<=rsp_rdata;error_q<=rsp_err;end
  end
endmodule
