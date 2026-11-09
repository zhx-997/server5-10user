// SPDX-License-Identifier: MIT
// 双缓冲计算与数据搬运保持 P7 调度；结果 SRAM 增加复位输入。
module kwt43_core #(parameter [31:0] MEM_BASE=0,MEM_BYTES=0,parameter PACK_LOW_FIRST=1)(
  input wire clk,rst_n,task_valid,output wire task_ready,
  input wire [31:0] task_x,task_w,task_b,task_y,input wire [3:0] task_layer,
  input wire [11:0] task_scales,output wire done_valid,input wire done_ready,
  output reg [31:0] status,sat_count,core_cycles,output wire busy,
  output wire mem_valid,input wire mem_ready,output wire [31:0] mem_addr,mem_wdata,
  output wire mem_read,input wire ret_valid,output wire ret_ready,input wire [31:0] ret_rdata,input wire ret_err
);
  localparam IDLE=0,CHECK=1,X_START=2,X_WAIT=3,FIRST_START=4,FIRST_WAIT=5,
    BEGIN_TILE=6,NEXT_START=7,NEXT_WAIT=8,PREV_START=9,PREV_WAIT=10,JOIN_TILE=11,LAST_START=12,LAST_WAIT=13,COMPLETE=14;
  reg [3:0] state,group_n;
  reg [31:0] xb,wb,bb,yb;
  reg [11:0] scales;
  reg [3:0] layer;
  wire dma_start=state==X_START||state==FIRST_START||state==NEXT_START||state==PREV_START||state==LAST_START;
  wire write_job=state==PREV_START||state==LAST_START;
  wire weights_job=state!=X_START;
  wire [3:0] dma_group=state==NEXT_START?group_n+1'b1:state==PREV_START?group_n-1'b1:group_n;
  reg dma_write,dma_page;
  wire rd_done,wr_done,rv,wv,rr,wr,x_write,w_write,b_write,y_read;
  wire [1:0] rd_error,wr_error,w_quad;
  wire [4:0] x_block;
  wire [5:0] value_k;
  wire [63:0] values,loaded_keys;
  wire [3:0] bias_index;
  wire [31:0] bias_data,read_addr,write_addr,write_data;
  wire [6:0] y_rd_row;
  wire [255:0] y_vector;
  reg [511:0] biases[0:1];
  reg [63:0] y_keys[0:1],w_keys[0:1];
  wire dma_done=rd_done||wr_done;
  wire [1:0] dma_error=dma_write?wr_error:rd_error;
  wire dma_failed=dma_done && dma_error!=0;
  assign mem_valid=rv||wv;assign mem_read=!dma_write;
  assign mem_addr=dma_write?write_addr:read_addr;assign mem_wdata=write_data;
  assign ret_ready=dma_write?wr:rr;
  assign task_ready=rst_n&&state==IDLE;assign busy=state!=IDLE;assign done_valid=rst_n&&state==COMPLETE;
  function automatic range_ok(input [31:0] a,n);
    reg [32:0] limit,finish;
    begin limit={1'b0,MEM_BASE}+{1'b0,MEM_BYTES};finish={1'b0,a}+{1'b0,n};
      range_ok=MEM_BYTES!=0&&a[1:0]==0&&a>=MEM_BASE&&finish<=limit&&limit<=33'h100000000;end
  endfunction
  function automatic overlap(input [31:0] a,alen,b,blen);
    overlap={1'b0,a}<({1'b0,b}+{1'b0,blen})&&{1'b0,b}<({1'b0,a}+{1'b0,alen});
  endfunction
  wire config_ok=range_ok(xb,16384)&&range_ok(wb,65536)&&range_ok(bb,1024)&&range_ok(yb,65536)
    && !overlap(xb,16384,wb,65536)&&!overlap(xb,16384,bb,1024)&&!overlap(xb,16384,yb,65536)
    && !overlap(wb,65536,bb,1024)&&!overlap(wb,65536,yb,65536)&&!overlap(bb,1024,yb,65536);
  always @(posedge clk)if(dma_start)begin dma_write<=write_job;dma_page<=dma_group[0];end
  kwt43_reader #(.PACK_LOW_FIRST(PACK_LOW_FIRST)) reader(.clk(clk),.rst_n(rst_n),
    .start(dma_start&&!write_job),.weights(weights_job),.group_index(dma_group),.sx(scales[3:0]),.sw(scales[7:4]),
    .xb(xb),.wb(wb),.bb(bb),.done(rd_done),.error(rd_error),.mem_valid(rv),.addr(read_addr),.mem_ready(mem_ready&&!dma_write),
    .ret_valid(ret_valid&&!dma_write),.ret_err(ret_err),.ret_data(ret_rdata),.ret_ready(rr),
    .x_write(x_write),.w_write(w_write),.b_write(b_write),.x_block(x_block),.value_k(value_k),.w_quad(w_quad),
    .values(values),.bias_index(bias_index),.bias_data(bias_data),.output_keys(loaded_keys));
  kwt43_writer #(.PACK_LOW_FIRST(PACK_LOW_FIRST)) writer(.clk(clk),.rst_n(rst_n),
    .start(dma_start&&write_job),.group_index(dma_group),.sy(scales[11:8]),.keys(y_keys[dma_group[0]]),.yb(yb),
    .done(wr_done),.error(wr_error),.mem_valid(wv),.addr(write_addr),.wdata(write_data),.mem_ready(mem_ready&&dma_write),
    .ret_valid(ret_valid&&dma_write),.ret_err(ret_err),.ret_ready(wr),
    .y_read(y_read),.y_addr(y_rd_row),.y_vector(y_vector));
  wire operand_read,x_rv,compute_done,result_commit;
  wire [1:0] w_valid;
  wire [255:0] wq[0:1];
  wire [127:0] xs;
  wire [3:0] tile;wire [5:0] k;
  wire [6:0] row_m;wire [255:0] result_y;wire [15:0] sat;
`ifndef SYNTHESIS
  wire [639:0] mac_acc;
`endif
  wire w_rv=w_valid[group_n[0]];
  wire compute_clear=state==IDLE||state==COMPLETE||dma_failed;
  kwt43_xram xbuffer(.clk(clk),.rst_n(rst_n),.wr_en(x_write),.wr_block(x_block),.wr_k(value_k),
    .wr_data(values),.rd_en(operand_read),.rd_tile(tile),.rd_k(k),.rd_valid(x_rv),.rd_data(xs));
  genvar p;
  generate for(p=0;p<2;p=p+1)begin: pages
    kwt43_wram weights(.clk(clk),.rst_n(rst_n),.wr_en(w_write&&dma_page==p),.wr_quad(w_quad),.wr_k(value_k),
      .wr_data(values),.rd_en(operand_read&&group_n[0]==p),.rd_k(k),.rd_valid(w_valid[p]),.rd_data(wq[p]));
    always @(posedge clk)begin
      if(b_write&&dma_page==p)biases[p][bias_index*32+:32]<=bias_data;
      if(rd_done&&dma_page==p)w_keys[p]<=loaded_keys;
      if(state==BEGIN_TILE&&group_n[0]==p)y_keys[p]<=w_keys[p];
    end
  end endgenerate
  kwt43_compute compute(.clk(clk),.rst_n(rst_n),.start(state==BEGIN_TILE),.clear(compute_clear),
    .biases(biases[group_n[0]]),.rd_en(operand_read),.tile(tile),.k(k),.pair_valid(x_rv&&w_rv),.xs(xs),
    .weights(wq[group_n[0]]),.commit(result_commit),.row(row_m),.y(result_y),.saturated(sat),.done(compute_done)
`ifndef SYNTHESIS
    ,.acc(mac_acc)
`endif
  );
  kwt43_yram outputs(.clk(clk),.rst_n(rst_n),.wr_en(result_commit),.wr_page(group_n[0]),.wr_row(row_m),.wr_data(result_y),
    .rd_en(y_read),.rd_page(dma_page),.rd_row(y_rd_row),.rd_data(y_vector));
  function automatic [4:0] pop16(input [15:0] bits);
    integer i;begin pop16=0;for(i=0;i<16;i=i+1)pop16=pop16+bits[i];end
  endfunction
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin state<=IDLE;group_n<=0;status<=0;sat_count<=0;core_cycles<=0;
      xb<=0;wb<=0;bb<=0;yb<=0;layer<=0;scales<=0;end
    else begin
      if(state!=IDLE&&state!=COMPLETE)core_cycles<=core_cycles+1'b1;
      if(result_commit)sat_count<=sat_count+pop16(sat);
      if(dma_failed)begin status<={30'd0,dma_error};state<=COMPLETE;end
      else case(state)
        IDLE:if(task_valid)begin
          xb<=task_x;wb<=task_w;bb<=task_b;yb<=task_y;layer<=task_layer;scales<=task_scales;
          status<=0;sat_count<=0;core_cycles<=0;group_n<=0;state<=CHECK;
        end
        CHECK:if(layer>=12)begin status<=4;state<=COMPLETE;end
              else if(!config_ok)begin status<=1;state<=COMPLETE;end else state<=X_START;
        X_START:state<=X_WAIT;
        X_WAIT:if(dma_done)state<=FIRST_START;
        FIRST_START:state<=FIRST_WAIT;
        FIRST_WAIT:if(dma_done)state<=BEGIN_TILE;
        BEGIN_TILE:state<=group_n==15?PREV_START:NEXT_START;
        NEXT_START:state<=NEXT_WAIT;
        NEXT_WAIT:if(dma_done)state<=group_n==0?JOIN_TILE:PREV_START;
        PREV_START:state<=PREV_WAIT;
        PREV_WAIT:if(dma_done)state<=JOIN_TILE;
        JOIN_TILE:if(compute_done)begin
          if(group_n==15)state<=LAST_START;
          else begin group_n<=group_n+1'b1;state<=BEGIN_TILE;end
        end
        LAST_START:state<=LAST_WAIT;
        LAST_WAIT:if(dma_done)state<=COMPLETE;
        COMPLETE:if(done_ready)state<=IDLE;
        default:begin status<=32'hff;state<=COMPLETE;end
      endcase
    end
  end
endmodule
