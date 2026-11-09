// SPDX-License-Identifier: MIT
// 单事务 ICB 主机：命令和响应分别寄存，两个方向均由状态寄存器控制握手。
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
  wire accept=req_valid&&req_ready;
  wire command=cmd_valid&&cmd_ready;
  wire response=rsp_valid&&rsp_ready;
  assign req_ready=rst_n&&state==EMPTY;
  assign cmd_valid=rst_n&&state==SEND;
  assign cmd_addr=addr_q;
  assign cmd_wdata=data_q;
  assign cmd_read=read_q;
  assign cmd_size=2'b10;
  assign rsp_ready=rst_n&&(state==SEND||state==WAIT_RSP);
  assign ret_valid=rst_n&&state==HOLD_RSP;
  assign ret_rdata=response_q;
  assign ret_err=error_q;
  assign idle=state==EMPTY;
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)state<=EMPTY;
    else case(state)
      EMPTY:if(accept)state<=SEND;
      SEND:if(command)state<=response?HOLD_RSP:WAIT_RSP;
      WAIT_RSP:if(response)state<=HOLD_RSP;
      HOLD_RSP:if(ret_ready)state<=EMPTY;
      default:state<=EMPTY;
    endcase
  end
  always @(posedge clk)begin
    if(accept)begin addr_q<=req_addr;data_q<=req_wdata;read_q<=req_read;end
    if(response)begin response_q<=rsp_rdata;error_q<=rsp_err;end
  end
`ifndef SYNTHESIS
  always @(posedge clk)if(rst_n&&state==SEND&&response&&!command)
    $fatal(1,"ICB_RESPONSE_BEFORE_COMMAND");
`endif
endmodule
