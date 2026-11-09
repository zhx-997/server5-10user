// SPDX-License-Identifier: MIT
// 两页结果存储器的请求在下降沿固定，读页选择与实际 SRAM 采样对齐。
module kwt43_yram(
  input wire clk,rst_n,wr_en,wr_page,input wire [6:0] wr_row,input wire [255:0] wr_data,
  input wire rd_en,rd_page,input wire [6:0] rd_row,output wire [255:0] rd_data
);
  reg selected,read_sampled,page_sampled;
  wire [255:0] q[0:1];
  always @(negedge clk or negedge rst_n)
    if(!rst_n)read_sampled<=0;else read_sampled<=rd_en;
  always @(negedge clk)if(rst_n&&rd_en)page_sampled<=rd_page;
  always @(posedge clk)if(read_sampled)selected<=page_sampled;
  genvar p,l;
  generate for(p=0;p<2;p=p+1)begin: page
    wire write_this=wr_en && wr_page==p;
    wire read_this=rd_en && rd_page==p;
    for(l=0;l<16;l=l+1)begin: lane
      reg request_enable,request_write;
      reg [6:0] request_address;
      reg [15:0] request_data;
      always @(negedge clk or negedge rst_n)begin
        if(!rst_n)begin request_enable<=0;request_write<=0;end
        else begin request_enable<=write_this||read_this;request_write<=write_this;end
      end
      always @(negedge clk)begin
        if(rst_n&&(write_this||read_this))request_address<=write_this?wr_row:rd_row;
        if(rst_n&&write_this)request_data<=wr_data[16*l+:16];
      end
      kwt_sp_ram #(.AW(7)) ram(.clk(clk),.en(request_enable),.we(request_write),
        .addr(request_address),.wdata(request_data),.rdata(q[p][16*l+:16]));
    end
  end endgenerate
  assign rd_data=q[selected];
endmodule
