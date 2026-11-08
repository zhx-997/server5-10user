// SPDX-License-Identifier: MIT
// Four entropy streams share one ordered 32-bit ICB channel. Reservation of
// each returning word prevents overfilling an unpacker under arbitrary stalls.
module kwt43_reader #(parameter PACK_LOW_FIRST=1)(
  input wire clk,rst_n,start,weights,input wire [3:0] group_index,
  input wire [3:0] sx,sw,input wire [31:0] xb,wb,bb,
  output wire done,output reg [1:0] error,
  output wire mem_valid,output wire [31:0] addr,input wire mem_ready,
  input wire ret_valid,ret_err,input wire [31:0] ret_data,output wire ret_ready,
  output wire x_write,w_write,b_write,output wire [4:0] x_block,
  output wire [5:0] value_k,output wire [1:0] w_quad,
  output wire [63:0] values,output wire [3:0] bias_index,
  output wire [31:0] bias_data,output wire [63:0] output_keys
);
  localparam IDLE=0,HEADER_REQ=1,HEADER_WAIT=2,STREAM=3,BIAS_REQ=4,BIAS_WAIT=5,DRAIN=6,FINISH=7;
  reg [2:0] state;
  reg is_w,pending;
  reg [3:0] scale,group_q,bias_q;
  reg [1:0] header_stream,round_robin,pending_stream;
  reg [3:0] header_word;
  reg [10:0] remaining[0:3];
  reg [31:0] cursor[0:3];
  reg [31:0] keys[0:3][0:7];
  reg [15:0] ykeys[0:3];
  reg [10:0] symbol;
  reg [4:0] block_row;
  reg [5:0] feature;
  reg [31:0] header_addr,bias_addr;
  wire [31:0] canonical=PACK_LOW_FIRST?ret_data:{ret_data[15:0],ret_data[31:16]};
  wire [3:0] symbol_valid,room,last_ok,literal;
  wire [2:0] level[0:3];
  wire signed [16:0] tokens[0:3];
  reg selected_valid;
  reg [1:0] selected;
  integer n,ix;
  always @* begin
    selected=round_robin;selected_valid=0;
    for(n=0;n<4;n=n+1)begin
      ix=(round_robin+n)&3;
      if(!selected_valid && remaining[ix]!=0 && level[ix]+((pending&&pending_stream==ix)?1:0)<4)begin
        selected=ix[1:0];selected_valid=1;
      end
    end
  end
  assign mem_valid=rst_n && (state==HEADER_REQ || state==BIAS_REQ || (state==STREAM&&selected_valid));
  assign addr=state==HEADER_REQ?header_addr:state==BIAS_REQ?bias_addr:cursor[selected];
  wire issue=mem_valid && mem_ready;
  // 返回就绪由预留槽位或当前可用槽位决定，避免依赖本拍请求握手。
  assign ret_ready=rst_n && (state==HEADER_WAIT || state==BIAS_WAIT ||
                    ((state==STREAM||state==DRAIN) && (pending || (state==STREAM&&selected_valid))));
  wire acknowledge=ret_valid && ret_ready;
  wire [1:0] return_stream=pending?pending_stream:selected;
  wire consume=state==STREAM && &symbol_valid && !(acknowledge&&ret_err);
  wire final_symbol=is_w?symbol==255:symbol==1599;
  genvar s;
  generate for(s=0;s<4;s=s+1)begin: stream
    wire [31:0] key_word=is_w?keys[s][0]:keys[s][feature[5:3]];
    wire [3:0] key=is_w?key_word[4*symbol[1:0]+:4]:key_word[4*feature[2:0]+:4];
    kwt43_unpack unpack(.clk(clk),.rst_n(rst_n),.clear(state!=STREAM),
      .push(state==STREAM&&acknowledge&&!ret_err&&return_stream==s),.word(canonical),
      .key(key),.shift(scale),.consume(consume),.room(room[s]),.level(level[s]),
      .valid(symbol_valid[s]),.absolute(literal[s]),.tail_clean(last_ok[s]),.value(tokens[s]));
    assign output_keys[16*s+:16]=ykeys[s];
  end endgenerate
  reg emit,emit_w;
  reg [4:0] saved_block;
  reg [5:0] saved_k;
  reg [1:0] saved_quad;
  reg [63:0] saved_values;
  reg signed [15:0] previous[0:3];
  wire [15:0] decoded[0:3];
  generate for(s=0;s<4;s=s+1)begin: expand
    wire [15:0] prediction=(is_w || literal[s] || block_row==0)?16'd0:previous[s];
    assign decoded[s]=tokens[s][15:0]+prediction;
  end endgenerate
  assign x_write=rst_n && emit && !emit_w;
  assign w_write=rst_n && emit && emit_w;
  assign x_block=saved_block;assign value_k=saved_k;assign w_quad=saved_quad;assign values=saved_values;
  assign b_write=state==BIAS_WAIT && acknowledge && !ret_err;
  assign bias_index=bias_q;assign bias_data=ret_data;
  assign done=state==FINISH;
  integer j;
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n)emit<=0;
    else emit<=consume;
  end
  always @(posedge clk)begin
    if(consume)begin
      emit_w<=is_w;saved_block<=block_row;saved_k<=is_w?symbol[7:2]:feature;saved_quad<=symbol[1:0];
      for(integer a=0;a<4;a=a+1)begin
        saved_values[16*a+:16]<=decoded[a]<<scale;
        previous[a]<=decoded[a];
      end
    end
    if(state==HEADER_WAIT&&acknowledge&&!ret_err&&header_word!=0)begin
      if(is_w)begin keys[header_stream][0]<={16'd0,canonical[15:0]};ykeys[header_stream]<=canonical[31:16];end
      else keys[header_stream][header_word-1]<=canonical;
    end
  end
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
      state<=IDLE;error<=0;is_w<=0;pending<=0;pending_stream<=0;round_robin<=0;header_stream<=0;header_word<=0;
      symbol<=0;feature<=0;block_row<=0;header_addr<=0;bias_addr<=0;bias_q<=0;scale<=0;group_q<=0;
      for(j=0;j<4;j=j+1)begin remaining[j]<=0;cursor[j]<=0;end
    end else case(state)
      IDLE:if(start)begin
        is_w<=weights;scale<=weights?sw:sx;group_q<=group_index;error<=0;pending<=0;
        header_stream<=0;header_word<=0;symbol<=0;feature<=0;block_row<=0;round_robin<=0;bias_q<=0;
        header_addr<=weights?wb+{16'd0,group_index,12'd0}:xb;
        bias_addr<=bb+{22'd0,group_index,6'd0};
        state<=HEADER_REQ;
      end
      HEADER_REQ:if(issue)state<=HEADER_WAIT;
      HEADER_WAIT:if(acknowledge)begin
        if(ret_err)begin error<=2;state<=DRAIN;end
        else if(header_word==0)begin
          if(canonical==0 || canonical>(is_w?160:1000))begin error<=1;state<=DRAIN;end
          else begin remaining[header_stream]<=canonical[10:0];header_word<=1;header_addr<=header_addr+4;state<=HEADER_REQ;end
        end else if(is_w || header_word==8)begin
          cursor[header_stream]<=header_addr+4;
          if(header_stream==3)state<=STREAM;
          else begin
            header_stream<=header_stream+1'b1;header_word<=0;
            header_addr<=is_w?wb+{16'd0,group_q,12'd0}+{20'd0,header_stream+2'd1,10'd0}:
                             xb+{18'd0,header_stream+2'd1,12'd0};
            state<=HEADER_REQ;
          end
        end else begin header_word<=header_word+1'b1;header_addr<=header_addr+4;state<=HEADER_REQ;end
      end
      STREAM:begin
        pending<=(pending&&!acknowledge)||(issue&&!(acknowledge&&!pending));
        if(issue)begin
          pending_stream<=selected;remaining[selected]<=remaining[selected]-1'b1;cursor[selected]<=cursor[selected]+4;
          round_robin<=selected+1'b1;
        end
        if(acknowledge&&ret_err)begin error<=2;state<=DRAIN;end
        else if(consume)begin
          if(final_symbol)begin
            if(!(&last_ok) || remaining[0]!=0 || remaining[1]!=0 || remaining[2]!=0 || remaining[3]!=0 || pending || issue)begin
              error<=1;state<=DRAIN;
            end else state<=is_w?BIAS_REQ:DRAIN;
          end else begin
            symbol<=symbol+1'b1;
            if(!is_w)begin
              if(block_row==24)begin block_row<=0;feature<=feature+1'b1;end
              else block_row<=block_row+1'b1;
            end
          end
        end else if(!pending && !issue && remaining[0]==0 && remaining[1]==0 && remaining[2]==0 && remaining[3]==0)begin
          error<=1;state<=DRAIN;
        end
      end
      BIAS_REQ:if(issue)state<=BIAS_WAIT;
      BIAS_WAIT:if(acknowledge)begin
        if(ret_err)begin error<=2;state<=DRAIN;end
        else if(bias_q==15)state<=DRAIN;
        else begin bias_q<=bias_q+1'b1;bias_addr<=bias_addr+4;state<=BIAS_REQ;end
      end
      DRAIN:begin
        if(acknowledge)pending<=0;
        if(!pending&&!emit)state<=FINISH;
      end
      FINISH:state<=IDLE;
      default:state<=IDLE;
    endcase
  end
endmodule
