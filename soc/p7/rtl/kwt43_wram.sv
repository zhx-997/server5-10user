// SPDX-License-Identifier: MIT
// 每页保存十六列，每个写入节拍更新其中四列。
module kwt43_wram(
  input wire clk,rst_n,wr_en,input wire [1:0] wr_quad,input wire [5:0] wr_k,
  input wire [63:0] wr_data,input wire rd_en,input wire [5:0] rd_k,
  output reg rd_valid,output wire [255:0] rd_data
);
  genvar l;
  generate for(l=0;l<16;l=l+1)begin: lane
    wire write_this=wr_en && wr_quad==l/4;
    wire [6:0] address={1'b0,write_this?wr_k:rd_k};
    reg request_enable,request_write;
    reg [6:0] request_address;
    reg [15:0] request_data;
    // 各列按自己的写使能保存数据，下降沿后保持到宏的上升沿采样。
    always @(negedge clk or negedge rst_n)begin
      if(!rst_n)begin request_enable<=0;request_write<=0;end
      else begin request_enable<=write_this||rd_en;request_write<=write_this;end
    end
    always @(negedge clk)begin
      if(rst_n&&(write_this||rd_en))request_address<=address;
      if(rst_n&&write_this)request_data<=wr_data[16*(l%4)+:16];
    end
    kwt_sp_ram #(.AW(7)) ram(.clk(clk),.en(request_enable),.we(request_write),
      .addr(request_address),.wdata(request_data),.rdata(rd_data[16*l+:16]));
  end endgenerate
  always @(posedge clk or negedge rst_n)
    if(!rst_n)rd_valid<=0;else rd_valid<=rd_en;
endmodule
