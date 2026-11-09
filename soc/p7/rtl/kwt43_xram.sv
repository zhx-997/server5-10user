// SPDX-License-Identifier: MIT
// 八个条带分别保存输入行；每个写入节拍更新四个条带，填充行 99 不写入。
module kwt43_xram(
  input wire clk,rst_n,wr_en,input wire [4:0] wr_block,input wire [5:0] wr_k,
  input wire [63:0] wr_data,input wire rd_en,input wire [3:0] rd_tile,input wire [5:0] rd_k,
  output reg rd_valid,output wire [127:0] rd_data
);
  genvar s;
  generate for(s=0;s<8;s=s+1)begin: stripe
    wire write_this=wr_en && wr_block[0]==(s/4) && !(wr_block==24 && s==3);
    wire [9:0] address=write_this ? {1'b0,wr_block[4:1],wr_k} : {rd_tile,rd_k};
    reg request_enable,request_write;
    reg [9:0] request_address;
    reg [15:0] request_data;
    // 请求在下降沿固定，宏在随后的上升沿执行原定的读写。
    always @(negedge clk or negedge rst_n)begin
      if(!rst_n)begin request_enable<=0;request_write<=0;end
      else begin request_enable<=write_this||rd_en;request_write<=write_this;end
    end
    always @(negedge clk)begin
      if(rst_n&&(write_this||rd_en))request_address<=address;
      if(rst_n&&write_this)request_data<=wr_data[16*(s%4)+:16];
    end
    kwt_sp_ram #(.AW(10)) ram(.clk(clk),.en(request_enable),.we(request_write),
      .addr(request_address),.wdata(request_data),.rdata(rd_data[16*s+:16]));
  end endgenerate
  reg read_sampled;
  always @(negedge clk or negedge rst_n)
    if(!rst_n)read_sampled<=0;else read_sampled<=rd_en;
  always @(posedge clk or negedge rst_n)
    if(!rst_n)rd_valid<=0;else rd_valid<=read_sampled;
endmodule
