// SPDX-License-Identifier: MIT
// Four independently coded column subsets run in parallel. The memory
// arbiter drains complete 32-bit words and preserves each stream's order.
module kwt43_writer #(parameter PACK_LOW_FIRST=1)(
  input wire clk,rst_n,start,input wire [3:0] group_index,input wire [3:0] sy,
  input wire [63:0] keys,input wire [31:0] yb,
  output wire done,output reg [1:0] error,
  output wire mem_valid,output wire [31:0] addr,wdata,input wire mem_ready,
  input wire ret_valid,ret_err,output wire ret_ready,
  output wire y_read,output wire [6:0] y_addr,input wire [255:0] y_vector
);
  localparam IDLE=0,HEAD_REQ=1,HEAD_WAIT=2,DATA=3,DRAIN=4,FINISH=5;
  localparam STOP=0,READ_FIRST=1,LATCH_ROW=2,SYMBOLS=3,ENDED=4;
  reg [2:0] state,producer;
  reg [3:0] scale,group_q;
  reg [63:0] key_q;
  reg [1:0] header_stream,round_robin;
  reg [8:0] next_word[0:3];
  reg pending;
  reg [6:0] row;
  reg [1:0] lane;
  reg [255:0] current;
  wire [3:0] room,empty,word_valid;
  wire [31:0] words[0:3];
  reg selected_valid;reg [1:0] selected;
  integer n,ix;
  always @*begin
    selected=round_robin;selected_valid=0;
    for(n=0;n<4;n=n+1)begin
      ix=(round_robin+n)&3;
      if(!selected_valid&&word_valid[ix])begin selected=ix[1:0];selected_valid=1;end
    end
  end
  assign mem_valid=rst_n && (state==HEAD_REQ || (state==DATA&&selected_valid));
  assign addr=yb+{16'd0,group_q,12'd0}+
              (state==HEAD_REQ?{20'd0,header_stream,10'd0}:{20'd0,selected,10'd0}+{21'd0,next_word[selected],2'd0});
  wire [31:0] canonical=state==HEAD_REQ?{16'd0,key_q[16*header_stream+:16]}:words[selected];
  assign wdata=PACK_LOW_FIRST?canonical:{canonical[15:0],canonical[31:16]};
  wire request=mem_valid&&mem_ready;
  // 返回就绪与请求 ready 分离；响应有效仍由主机实际收到的应答决定。
  assign ret_ready=rst_n && (state==HEAD_WAIT || ((state==DATA||state==DRAIN)&&(pending||(state==DATA&&selected_valid))));
  wire acknowledge=ret_valid&&ret_ready;
  wire advance=&room;
  wire issue=producer==SYMBOLS && advance;
  wire clear_pipe=start || state==IDLE || state==FINISH || state==DRAIN;
  reg v1,v2,v3;
  reg [1:0] l1;
  reg first1;
  wire encoder_done=producer==ENDED&&!v1&&!v2&&!v3;
  assign done=state==FINISH;
  assign y_read=rst_n && (producer==READ_FIRST || (issue&&lane==2&&row!=98));
  assign y_addr=producer==READ_FIRST?7'd0:row+1'b1;
  genvar s;
  generate for(s=0;s<4;s=s+1)begin: stream
    reg signed [15:0] q1,q2,previous[0:3];
    reg [3:0] k1,k2;
    reg [16:0] zigzag2;
    reg [19:0] token3;reg [4:0] width3;
    wire signed [15:0] sample=$signed(current[16*(4*lane+s)+:16]);
    wire signed [16:0] twice=$signed({sample,1'b0})>>>scale;
    wire signed [15:0] base=$signed(twice[16:1]);
    wire signed [15:0] ceiling=$signed(16'h7fff)>>>scale;
    wire signed [15:0] quantized=base==ceiling?base:base+{15'd0,twice[0]};
    wire signed [15:0] predictor=first1?16'sd0:previous[l1];
    wire signed [16:0] difference=$signed({q1[15],q1})-$signed({predictor[15],predictor});
    wire [16:0] quotient=zigzag2>>k2;
    wire [15:0] remainder=zigzag2&((16'd1<<k2)-1'b1);
    wire [2:0] prefix_length={1'b0,quotient[1:0]}+1'b1;
    wire [19:0] short_code=({4'd0,remainder}<<prefix_length)|((20'd1<<quotient[1:0])-1'b1);
    wire [15:0] literal=q2&(16'hffff>>scale);
    wire pop=state==DATA&&request&&selected==s;
    kwt_rice_pack packer(.clk(clk),.rst_n(rst_n),.clear(clear_pipe),.token_valid(v3&&advance),
      .token(token3),.width(width3),.flush(encoder_done),.room(room[s]),.empty(empty[s]),
      .word_valid(word_valid[s]),.pop(pop),.word(words[s]));
    always @(posedge clk)begin
      if(advance&&issue)begin q1<=quantized;k1<=key_q[16*s+4*lane+:4];end
      if(advance&&v1)begin previous[l1]<=q1;q2<=q1;k2<=k1;zigzag2<=(difference<<1)^{17{difference[16]}};end
      if(advance&&v2)begin
        token3<=quotient>=4?{literal,4'hf}:short_code;
        width3<=quotient>=4?5'd20-{1'b0,scale}:{1'b0,k2}+prefix_length;
      end
    end
  end endgenerate
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin v1<=0;v2<=0;v3<=0;end
    else if(clear_pipe)begin v1<=0;v2<=0;v3<=0;end
    else if(advance)begin v1<=issue;v2<=v1;v3<=v2;end
  end
  always @(posedge clk)begin
    if(advance&&issue)begin l1<=lane;first1<=row==0;end
    if(producer==LATCH_ROW || (issue&&lane==3&&row!=98))current<=y_vector;
  end
  integer j;
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin state<=IDLE;producer<=STOP;error<=0;scale<=0;group_q<=0;key_q<=0;
      header_stream<=0;round_robin<=0;row<=0;lane<=0;pending<=0;
      for(j=0;j<4;j=j+1)next_word[j]<=1;
    end else begin
      if(clear_pipe)begin producer<=STOP;row<=0;lane<=0;end
      else case(producer)
        READ_FIRST:producer<=LATCH_ROW;
        LATCH_ROW:producer<=SYMBOLS;
        SYMBOLS:if(issue)begin
          lane<=lane+1'b1;
          if(lane==3)begin
            if(row==98)producer<=ENDED;else row<=row+1'b1;
          end
        end
        default:begin end
      endcase
      case(state)
        IDLE:if(start)begin
          scale<=sy;group_q<=group_index;key_q<=keys;header_stream<=0;round_robin<=0;error<=0;pending<=0;
          for(j=0;j<4;j=j+1)next_word[j]<=1;
          state<=HEAD_REQ;
        end
        HEAD_REQ:if(request)state<=HEAD_WAIT;
        HEAD_WAIT:if(acknowledge)begin
          if(ret_err)begin error<=3;state<=DRAIN;end
          else if(header_stream==3)begin state<=DATA;producer<=READ_FIRST;end
          else begin header_stream<=header_stream+1'b1;state<=HEAD_REQ;end
        end
        DATA:begin
          pending<=(pending&&!acknowledge)||(request&&!(acknowledge&&!pending));
          if(request)begin next_word[selected]<=next_word[selected]+1'b1;round_robin<=selected+1'b1;end
          if(acknowledge&&ret_err)begin error<=3;state<=DRAIN;end
          else if(encoder_done&&(&empty)&&!pending&&!request)state<=FINISH;
        end
        DRAIN:begin
          if(acknowledge)pending<=0;
          if(!pending)state<=FINISH;
        end
        FINISH:state<=IDLE;
        default:state<=IDLE;
      endcase
    end
  end
endmodule
