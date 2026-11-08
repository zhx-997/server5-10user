`timescale 1ns/1ps
`include "e203_defines.v"
module tb_itcm_pipeline;
  reg clk=0, rst_n=0, cgstop=0;
  always #3.333333333 clk=~clk;
  reg [2:0] cv=0, cread=7, rr=7;
  wire [2:0] cr, rv, re;
  reg [`E203_ITCM_ADDR_WIDTH-1:0] ca[0:2];
  reg [63:0] wd[0:2];
  reg [7:0] wm[0:2];
  wire [63:0] rd[0:2];
  wire [31:0] lsu_rd, ext_rd;
  assign rd[1]={32'b0,lsu_rd};
  assign rd[2]={32'b0,ext_rd};
  wire active, hold_data, cs, we, ram_clk;
  wire [`E203_ITCM_RAM_AW-1:0] address;
  wire [7:0] mask;
  wire [63:0] din, dout;
  e203_itcm_ctrl dut (
    .itcm_active(active), .tcm_cgstop(cgstop),
    .ifu2itcm_icb_cmd_valid(cv[0]), .ifu2itcm_icb_cmd_ready(cr[0]),
    .ifu2itcm_icb_cmd_read(cread[0]), .ifu2itcm_icb_cmd_addr(ca[0]),
    .ifu2itcm_icb_cmd_wdata(wd[0]), .ifu2itcm_icb_cmd_wmask(wm[0]),
    .ifu2itcm_icb_rsp_valid(rv[0]), .ifu2itcm_icb_rsp_ready(rr[0]),
    .ifu2itcm_icb_rsp_err(re[0]), .ifu2itcm_icb_rsp_rdata(rd[0]),
    .ifu2itcm_holdup(hold_data),
    .lsu2itcm_icb_cmd_valid(cv[1]), .lsu2itcm_icb_cmd_ready(cr[1]),
    .lsu2itcm_icb_cmd_read(cread[1]), .lsu2itcm_icb_cmd_addr(ca[1]),
    .lsu2itcm_icb_cmd_wdata(wd[1][31:0]), .lsu2itcm_icb_cmd_wmask(wm[1][3:0]),
    .lsu2itcm_icb_rsp_valid(rv[1]), .lsu2itcm_icb_rsp_ready(rr[1]),
    .lsu2itcm_icb_rsp_err(re[1]), .lsu2itcm_icb_rsp_rdata(lsu_rd),
    .ext2itcm_icb_cmd_valid(cv[2]), .ext2itcm_icb_cmd_ready(cr[2]),
    .ext2itcm_icb_cmd_read(cread[2]), .ext2itcm_icb_cmd_addr(ca[2]),
    .ext2itcm_icb_cmd_wdata(wd[2][31:0]), .ext2itcm_icb_cmd_wmask(wm[2][3:0]),
    .ext2itcm_icb_rsp_valid(rv[2]), .ext2itcm_icb_rsp_ready(rr[2]),
    .ext2itcm_icb_rsp_err(re[2]), .ext2itcm_icb_rsp_rdata(ext_rd),
    .itcm_ram_cs(cs), .itcm_ram_we(we), .itcm_ram_addr(address),
    .itcm_ram_wem(mask), .itcm_ram_din(din), .itcm_ram_dout(dout),
    .clk_itcm_ram(ram_clk), .test_mode(1'b0), .clk(clk), .rst_n(rst_n)
  );
  // 使用 E203 随附的 SRAM 仿真模型，并保留未初始化数据的 X 状态。
  sirv_sim_ram #(.DP(1<<`E203_ITCM_RAM_AW), .DW(64), .MW(8), .AW(`E203_ITCM_RAM_AW), .FORCE_X2ZERO(0)) memory (
    .clk(ram_clk), .din(din), .addr(address), .cs(cs), .we(we), .wem(mask), .dout(dout)
  );
  reg [7:0] reference_bytes[0:1023];
  reg [63:0] expected[0:65535];
  integer owner[0:65535], accepted_cycle[0:65535];
  reg is_read[0:65535];
  integer head=0, tail=0, cycles=0, accepted=0, completed=0, aborted=0;
  integer per_port[0:2], stalled_cycles=0, hold_cycles=0, maximum_pending=0;
  reg [2:0] accepted_now=0, stalled=0;
  reg [63:0] stalled_data[0:2], last_ifu_data;
  integer last_owner=-1;
  integer seed=32'h20304007, random_value;
  integer random_cycles=20000;
  function automatic integer choose(input integer limit);
    integer value;
    begin value=$random(seed); choose=(value & 32'h7fffffff)%limit; end
  endfunction

  always @(posedge clk) begin
    cycles=cycles+1;
    accepted_now=0;
    if(rst_n) begin
      if(hold_data) begin
        if(head!=tail || last_owner!=0 || rd[0]!==last_ifu_data)
          $fatal(1,"ITCM_HOLD_DATA_INVALID cycle=%0d pending=%0d",cycles,tail-head);
        hold_cycles=hold_cycles+1;
      end
      if(dut.itcm_pending!==(tail-head))
        $fatal(1,"ITCM_PENDING_MISMATCH cycle=%0d hardware=%0d expected=%0d",cycles,dut.itcm_pending,tail-head);
      for(integer p=0;p<3;p=p+1) begin
        if(stalled[p] && (rv[p]!==1'b1 || rd[p]!==stalled_data[p]))
          $fatal(1,"ITCM_STALLED_RESPONSE_CHANGED port=%0d",p);
        stalled[p]=rv[p]&&!rr[p];
        stalled_data[p]=rd[p];
        if(stalled[p])stalled_cycles=stalled_cycles+1;
        if(cv[p]&&cr[p])begin
          if(tail>=65536)$fatal(1,"ITCM_SCOREBOARD_FULL");
          owner[tail]=p;is_read[tail]=cread[p];accepted_cycle[tail]=cycles;
          expected[tail]=0;
          for(integer b=0;b<(p==0?8:4);b=b+1)begin
            expected[tail][8*b+:8]=reference_bytes[ca[p]+b];
            if(!cread[p]&&wm[p][b])reference_bytes[ca[p]+b]=wd[p][8*b+:8];
          end
          tail=tail+1;accepted=accepted+1;accepted_now[p]=1;
        end
      end
      for(integer p=0;p<3;p=p+1)begin
        if(rv[p]&&rr[p])begin
          if(head==tail || owner[head]!=p)$fatal(1,"ITCM_RESPONSE_ORDER port=%0d head=%0d tail=%0d",p,head,tail);
          if(re[p]!==0)$fatal(1,"ITCM_RESPONSE_ERROR port=%0d",p);
          if(cycles-accepted_cycle[head]<2)$fatal(1,"ITCM_PIPELINE_LATENCY");
          if(is_read[head]&&rd[p]!==expected[head])
            $fatal(1,"ITCM_DATA_MISMATCH port=%0d sequence=%0d got=%h expected=%h",p,head,rd[p],expected[head]);
          last_owner=(is_read[head]?p:-1);
          if(p==0&&is_read[head])last_ifu_data=rd[0];
          head=head+1;completed=completed+1;per_port[p]=per_port[p]+1;
        end
      end
      if(tail-head>maximum_pending)maximum_pending=tail-head;
      if(tail-head>3)$fatal(1,"ITCM_OUTSTANDING_OVERFLOW");
      if(tail!=head&&active!==1'b1)$fatal(1,"ITCM_CLOCK_STOPPED_WITH_PENDING_RESPONSE");
    end else begin
      aborted=aborted+(tail-head);head=0;tail=0;stalled=0;last_owner=-1;
    end
  end

  task automatic one_access(input integer port_id,input bit read_request,
      input integer byte_address,input [63:0] data,input [7:0] byte_mask);
    integer target;
    begin
      @(negedge clk);target=completed+1;
      cv[port_id]=1;cread[port_id]=read_request;ca[port_id]=byte_address;
      wd[port_id]=data;wm[port_id]=byte_mask;
      do @(negedge clk);while(!accepted_now[port_id]);
      cv[port_id]=0;
      while(completed<target)@(negedge clk);
    end
  endtask
  task automatic initialize_memory;
    begin
      for(integer i=0;i<128;i=i+1)
        one_access(0,0,8*i,{32'hca000000+i,32'hac000000+i},8'hff);
    end
  endtask
  task automatic drain;
    integer elapsed;
    begin
      rr=7;elapsed=0;
      while(cv!=0||head!=tail)begin
        @(negedge clk);
        for(integer p=0;p<3;p=p+1)if(accepted_now[p])cv[p]=0;
        elapsed=elapsed+1;
        if(elapsed>100)$fatal(1,"ITCM_DRAIN_TIMEOUT");
      end
      repeat(4)@(negedge clk);
    end
  endtask
  initial begin
    random_value=$value$plusargs("SEED=%d",seed);
    for(integer p=0;p<3;p=p+1)begin ca[p]=0;wd[p]=0;wm[p]=0;per_port[p]=0;end
    repeat(6)@(negedge clk);rst_n=1;
    initialize_memory();
    one_access(0,1,0,0,0);
    repeat(5)@(negedge clk);
    if(!hold_data)$fatal(1,"ITCM_IFU_DATA_NOT_REUSABLE");
    for(integer lane=0;lane<8;lane=lane+1)begin
      one_access(2,0,4*(lane/4),64'h00000000a5a5a5a5,1<<(lane%4));
      if(hold_data)$fatal(1,"ITCM_EXTERNAL_WRITE_DID_NOT_INVALIDATE");
      one_access(0,1,0,0,0);
    end
    for(integer iteration=0;iteration<random_cycles;iteration=iteration+1)begin
      @(negedge clk);
      cgstop=(iteration%37==0);
      for(integer p=0;p<3;p=p+1)begin
        rr[p]=(choose(10)<6);
        if(!cv[p]||accepted_now[p])begin
          cv[p]=(choose(10)<(p==(iteration/100)%3?8:1));
          cread[p]=(p==0)||(choose(2)==0);
          ca[p]=(p==0?8*choose(128):4*choose(256));
          wd[p]={$random(seed),$random(seed)};
          wm[p]=choose(256);
        end
      end
    end
    drain();
    // 在响应被阻塞时复位，旧响应必须被清除。
    @(negedge clk);rr=0;cv=1;cread=7;ca[0]=0;
    do @(negedge clk);while(!accepted_now[0]);
    cv=0;
    while(!rv[0])@(negedge clk);
    repeat(5)@(negedge clk);rst_n=0;
    repeat(4)@(negedge clk);rst_n=1;rr=7;
    repeat(8)@(negedge clk);
    if(rv!=0||hold_data)$fatal(1,"ITCM_STALE_RESPONSE_AFTER_RESET");
    @(negedge clk);rr=0;cv=1;cread=7;ca[0]=16;
    while(tail-head<3)@(negedge clk);
    cv=0;
    repeat(5)@(negedge clk);rst_n=0;
    repeat(4)@(negedge clk);rst_n=1;rr=7;
    repeat(8)@(negedge clk);
    if(rv!=0||hold_data)$fatal(1,"ITCM_QUEUED_REQUEST_SURVIVED_RESET");
    initialize_memory();
    one_access(0,1,1016,0,0);
    one_access(1,1,1020,0,0);
    one_access(2,1,1016,0,0);
    drain();
    if(per_port[0]<100||per_port[1]<100||per_port[2]<100||stalled_cycles<100||hold_cycles<5||aborted!=4||maximum_pending!=3)
      $fatal(1,"ITCM_COVERAGE_INCOMPLETE ports=%0d,%0d,%0d stalls=%0d hold=%0d abort=%0d",per_port[0],per_port[1],per_port[2],stalled_cycles,hold_cycles,aborted);
    if(accepted!=completed+aborted)$fatal(1,"ITCM_TRANSACTION_COUNT_MISMATCH");
    $display("ITCM_PIPELINE_PASS accepted=%0d completed=%0d reset_aborted=%0d ports=%0d,%0d,%0d stalls=%0d reuse_cycles=%0d max_pending=%0d",accepted,completed,aborted,per_port[0],per_port[1],per_port[2],stalled_cycles,hold_cycles,maximum_pending);
    $finish;
  end
  initial begin #1000000;$fatal(1,"ITCM_TEST_TIMEOUT");end
endmodule
