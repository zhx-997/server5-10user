// SPDX-License-Identifier: MIT
// 16 位有符号乘法分为四个部分积和分段求和，共五级，每周期可接收新输入。
module kwt_mul16_pipe (
  input wire clk,rst_n,clear,in_valid,in_last,
  input wire signed [15:0] in_x,in_w,
  output wire out_valid,out_last,
  output reg signed [31:0] out_product
);
  reg [4:0] valid_pipe,last_pipe;
  reg [7:0] x_low,w_low;
  reg signed [7:0] x_high,w_high;
  reg [15:0] low_low;
  reg signed [15:0] high_low,low_high,high_high;
  reg [31:0] base_product;
  reg signed [16:0] cross_product;
  wire [31:0] shifted_cross={{7{cross_product[16]}},cross_product,8'b0};
  wire [12:0] lower_sum={1'b0,base_product[19:8]}+{1'b0,shifted_cross[19:8]};
  reg [11:0] base_upper,cross_upper;
  reg [19:0] joined_lower;
  reg carry_to_upper;
  assign out_valid=valid_pipe[4];
  assign out_last=last_pipe[4];
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin valid_pipe<=0;last_pipe<=0;end
    else begin
      valid_pipe<=clear?5'd0:{valid_pipe[3:0],in_valid};
      last_pipe<=clear?5'd0:{last_pipe[3:0],in_valid&&in_last};
    end
  end
  always @(posedge clk)begin
    if(in_valid)begin x_low<=in_x[7:0];x_high<=in_x[15:8];w_low<=in_w[7:0];w_high<=in_w[15:8];end
    if(valid_pipe[0])begin
      low_low<=x_low*w_low;
      high_low<=x_high*$signed({1'b0,w_low});
      low_high<=$signed({1'b0,x_low})*w_high;
      high_high<=x_high*w_high;
    end
    if(valid_pipe[1])begin
      base_product<={high_high,low_low};
      cross_product<=$signed({high_low[15],high_low})+$signed({low_high[15],low_high});
    end
    if(valid_pipe[2])begin
      base_upper<=base_product[31:20];cross_upper<=shifted_cross[31:20];
      joined_lower<={lower_sum[11:0],base_product[7:0]};carry_to_upper<=lower_sum[12];
    end
    if(valid_pipe[3])out_product<={base_upper+cross_upper+{11'd0,carry_to_upper},joined_lower};
  end
endmodule
