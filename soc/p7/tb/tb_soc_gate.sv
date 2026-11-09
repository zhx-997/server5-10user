`timescale 1ns/1ps
`include "e203_defines.v"
module tb_soc_gate;
  reg hfclk=0,lfclk=0,external_reset_n=0,bootrom_n=1;
  real input_delay_ns=1.0;
  wire clk,rst_n;
  always #3.333333333 hfclk=~hfclk;
  always #15258.7890625 lfclk=~lfclk;
  integer cycles=0,nice_requests=0,last_write_cycle=0,last_response_cycle=0;
  always @(posedge hfclk)cycles<=cycles+1;
  reg iv=0,iread=0;
  wire ir,irv,ire;
  reg [17:0] ia=0;
  reg [31:0] id=0;
  wire [31:0] ird;
  reg load_valid=0,load_read=0;
  reg [31:0] load_addr=0,load_data=0;
  wire load_ready,load_rvalid,load_error;
  wire [31:0] load_rdata;
  reg [31:0] observed;
  integer itcm_responses=0,load_responses=0;
  reg captured_itcm_error,captured_load_error;
  reg [31:0] captured_load_data;
  always @(posedge hfclk)if(rst_n)begin
    if(irv)begin
      captured_itcm_error=ire;
      itcm_responses=itcm_responses+1;
    end
    if(load_rvalid)begin
      captured_load_error=load_error;
      captured_load_data=load_rdata;
      load_responses=load_responses+1;
    end
  end
  kwt_e203_soc_top dut(
    .hfextclk(hfclk),.lfextclk(lfclk),.sys_clk(clk),.sys_rst_n(rst_n),
    .load_cmd_valid(load_valid),.load_cmd_ready(load_ready),.load_cmd_read(load_read),
    .load_cmd_addr(load_addr),.load_cmd_wdata(load_data),.load_cmd_wmask(4'hf),
    .load_rsp_valid(load_rvalid),.load_rsp_ready(1'b1),.load_rsp_err(load_error),.load_rsp_rdata(load_rdata),
    .itcm_cmd_valid(iv),.itcm_cmd_ready(ir),.itcm_cmd_read(iread),
    .itcm_cmd_addr(ia),.itcm_cmd_wdata(id),.itcm_cmd_wmask(4'hf),
    .itcm_rsp_valid(irv),.itcm_rsp_ready(1'b1),.itcm_rsp_err(ire),.itcm_rsp_rdata(ird),
    .io_pads_jtag_TCK_i_ival(1'b0),.io_pads_jtag_TMS_i_ival(1'b1),.io_pads_jtag_TDI_i_ival(1'b1),
    .io_pads_gpioA_i_ival(32'b0),.io_pads_gpioB_i_ival(32'b0),
    .io_pads_qspi0_dq_0_i_ival(1'b1),.io_pads_qspi0_dq_1_i_ival(1'b1),
    .io_pads_qspi0_dq_2_i_ival(1'b1),.io_pads_qspi0_dq_3_i_ival(1'b1),
    .io_pads_aon_erst_n_i_ival(external_reset_n),
    .io_pads_dbgmode0_n_i_ival(1'b1),.io_pads_dbgmode1_n_i_ival(1'b1),.io_pads_dbgmode2_n_i_ival(1'b1),
    .io_pads_bootrom_n_i_ival(bootrom_n),.io_pads_aon_pmu_dwakeup_n_i_ival(1'b1)
  );

  reg boot_monitor=0;
  integer boot_rom_first=0,boot_rom_jump=0,boot_itcm_first=0;
`ifndef GATE_LEVEL
  `define CPU dut.u_e203_subsys_top.u_e203_subsys_main.u_e203_cpu_top.u_e203_cpu
  `define COMMIT `CPU.u_e203_core.u_e203_exu.u_e203_exu_commit
  wire [31:0] pc=`COMMIT.alu_cmt_i_pc;
  always @(posedge clk)if(rst_n&&boot_monitor&&`COMMIT.alu_cmt_i_valid&&`COMMIT.alu_cmt_i_ready)begin
    if(pc==32'h1000)boot_rom_first=boot_rom_first+1;
    if(pc==32'h1004)boot_rom_jump=boot_rom_jump+1;
    if(pc==32'h80000000)boot_itcm_first=boot_itcm_first+1;
  end

  reg previous_nice_read=1;
  always @(posedge clk)if(rst_n&&boot_monitor)begin
    if(`CPU.nice_req_valid&&`CPU.nice_req_ready)begin
      nice_requests<=nice_requests+1;
      $display("CPU_NICE_REQUEST pc=%h inst=%h descriptor=%h",pc,`CPU.nice_req_inst,`CPU.nice_req_rs1);
    end
    if(`CPU.nice_icb_cmd_valid&&`CPU.nice_icb_cmd_ready)
      previous_nice_read<=`CPU.nice_icb_cmd_read;
    if(`CPU.nice_icb_rsp_valid&&`CPU.nice_icb_rsp_ready&&!previous_nice_read)last_write_cycle<=cycles;
    if(`CPU.nice_rsp_multicyc_valid&&`CPU.nice_rsp_multicyc_ready)last_response_cycle<=cycles;
  end
`endif
`ifdef GATE_LEVEL
`ifndef KWT_GATE_FUNCTIONAL
  wire [69:0] synchronous_outputs={ir,irv,ire,ird,load_ready,load_rvalid,load_error,load_rdata};
  reg [69:0] stable_outputs;
  reg output_window=0;
  // 外部接收器要求上升沿前 1ns、上升沿后 0.1ns 内输出保持稳定。
  always @(negedge hfclk)begin
    #(3.333333333-1.0);
    stable_outputs=synchronous_outputs;
    output_window=(rst_n===1'b1);
    #1.1;output_window=0;
  end
  always @(synchronous_outputs)begin
    if(output_window&&rst_n===1'b1&&synchronous_outputs!==stable_outputs)
      $fatal(1,"IO_OUTPUT_TIMING_VIOLATION time=%0t before=%h after=%h",$time,stable_outputs,synchronous_outputs);
  end
  initial begin
`ifdef KWT_SDF_MINIMUM
    input_delay_ns=0.1;
    $sdf_annotate("soc.sdf",dut,,,"MINIMUM");
`else
    input_delay_ns=1.0;
    $sdf_annotate("soc.sdf",dut,,,"MAXIMUM");
`endif
  end
`endif
`endif

  task automatic itcm_write(input integer word_index,input [31:0] data);
    integer target,started;
    begin
      // 最大、最小延迟仿真分别采用 1ns、0.1ns 外部输入到达时间。
      @(posedge hfclk);#(input_delay_ns);target=itcm_responses+1;started=cycles;iv=1;ia=4*word_index;id=data;
      do begin
        @(posedge hfclk);
        if(cycles-started>64)$fatal(1,"ITCM_COMMAND_TIMEOUT index=%0d ready=%b",word_index,ir);
      end while(ir!==1'b1);
      #(input_delay_ns);iv=0;
      while(itcm_responses<target)begin
        @(negedge hfclk);
        if(cycles-started>64)$fatal(1,"ITCM_RESPONSE_TIMEOUT index=%0d valid=%b responses=%0d",word_index,irv,itcm_responses);
      end
      if(captured_itcm_error!==0)$fatal(1,"ITCM load error index=%0d",word_index);
    end
  endtask
  task automatic transfer(input bit read_request,input [31:0] address,input [31:0] data,output [31:0] result);
    integer target,started;
    begin
      @(posedge hfclk);#(input_delay_ns);target=load_responses+1;started=cycles;load_valid=1;load_read=read_request;load_addr=address;load_data=data;
      do begin
        @(posedge hfclk);
        if(cycles-started>8192)$fatal(1,"SHARED_COMMAND_TIMEOUT address=%h",address);
      end while(load_ready!==1'b1);
      #(input_delay_ns);load_valid=0;
      while(load_responses<target)begin
        @(negedge hfclk);
        if(cycles-started>8192)$fatal(1,"SHARED_RESPONSE_TIMEOUT address=%h",address);
      end
      if(captured_load_error!==0)$fatal(1,"shared SRAM access error address=%h",address);
      result=captured_load_data;
    end
  endtask
  task automatic store_word(input [31:0] address,input [31:0] data);
    reg [31:0] unused;
    begin transfer(0,address,data,unused);end
  endtask
  task automatic read_word(input [31:0] address,output [31:0] data);
    begin transfer(1,address,0,data);end
  endtask

  task automatic boot_from_rom;
    reg [31:0] failure_code,trap_cause,trap_pc;
    begin
      @(negedge hfclk);external_reset_n=0;bootrom_n=0;
      repeat(32)@(negedge lfclk);
      boot_monitor=1;external_reset_n=1;
      wait(rst_n===1'b1);
      $display("SOC_BOOT_RESET_RELEASED time=%0t",$time);
      observed=0;
      while(observed!==32'h20300001)begin
        read_word(32'ha0000018,observed);
        if(observed!==0)begin
          failure_code=observed;
          read_word(32'ha000000c,trap_cause);
          read_word(32'ha0000010,trap_pc);
          $fatal(1,"CPU_SELFTEST_FAILED code=%h mcause=%h mepc=%h",failure_code,trap_cause,trap_pc);
        end
        read_word(32'ha000001c,observed);
      end
`ifndef GATE_LEVEL
      if(boot_rom_first==0||boot_rom_jump==0||boot_itcm_first==0)
        $fatal(1,"BOOT_ROM_CHAIN_MISSING first=%0d jump=%0d itcm=%0d",boot_rom_first,boot_rom_jump,boot_itcm_first);
`endif
      $display("SOC_BOOT_PASS ROM=00001000 ITCM=80000000 firmware_selftest=PASS");
      read_word(32'ha0000038,observed);
      if(observed!==1)$fatal(1,"MISALIGNED_LOAD_TRAP_RETURN_FAILED count=%h",observed);
      read_word(32'ha000003c,observed);
      if(observed!==1)$fatal(1,"SOFTWARE_INTERRUPT_RETURN_FAILED count=%h",observed);
    end
  endtask

  reg [31:0] firmware[0:4095],xwords[0:4095],wwords[0:16383],bias[0:255],expected[0:16383];
  reg [15:0] groups[0:63];
  string vector_dir,firmware_file;
  integer layer,start_cycle,begin_requests,checked,all_checked=0;
  localparam [31:0] XBASE=32'ha0001000,WBASE=32'ha0005000,BBASE=32'ha0016000,YBASE=32'ha0018000;
  initial begin
    if(!$value$plusargs("VEC_DIR=%s",vector_dir))$fatal(1,"VEC_DIR required");
    if(!$value$plusargs("FIRMWARE=%s",firmware_file))$fatal(1,"FIRMWARE required");
    for(integer i=0;i<4096;i=i+1)firmware[i]=0;
    $readmemh(firmware_file,firmware);
    // 先通过外部下载端口装载 SRAM，再由真实 AON 复位流程选择 ROM 启动。
    repeat(32)@(negedge lfclk);external_reset_n=1;
    wait(rst_n===1'b1);
    $display("SOC_DOWNLOAD_START time=%0t",$time);
    for(integer i=0;i<4096;i=i+1)itcm_write(i,firmware[i]);
    $display("SOC_DOWNLOAD_COMPLETE words=4096 time=%0t",$time);
    for(integer i=0;i<32;i=i+1)store_word(32'ha0000000+4*i,0);
    boot_from_rom();
    for(layer=0;layer<12;layer=layer+1)begin
      $readmemh($sformatf("%s/layer%02d_x.hex",vector_dir,layer),xwords);
      $readmemh($sformatf("%s/layer%02d_w.hex",vector_dir,layer),wwords);
      $readmemh($sformatf("%s/layer%02d_b.hex",vector_dir,layer),bias);
      $readmemh($sformatf("%s/layer%02d_wire.hex",vector_dir,layer),expected);
      $readmemh($sformatf("%s/layer%02d_groups.hex",vector_dir,layer),groups);
      for(integer i=0;i<16384;i=i+1)store_word(YBASE+4*i,32'h5a5aa5a5);
      start_cycle=cycles;begin_requests=nice_requests;
      for(integer i=0;i<4096;i=i+1)store_word(XBASE+4*i,xwords[i]);
      for(integer i=0;i<16384;i=i+1)store_word(WBASE+4*i,wwords[i]);
      for(integer i=0;i<256;i=i+1)store_word(BBASE+4*i,bias[i]);
      store_word(32'ha0000020,layer);store_word(32'ha0000024,XBASE);store_word(32'ha0000028,WBASE);
      store_word(32'ha000002c,BBASE);store_word(32'ha0000030,YBASE);store_word(32'ha0000000,layer+1);
      observed=0;
      while(observed!==layer+1)begin
        repeat(100)@(negedge hfclk);
        read_word(32'ha0000004,observed);
      end
      read_word(32'ha0000008,observed);
      if(observed!==0)$fatal(1,"CPU task failed layer=%0d status=%h",layer,observed);
`ifndef GATE_LEVEL
      if(nice_requests!=begin_requests+1)$fatal(1,"CPU did not issue exactly one NICE instruction");
      if(last_write_cycle<=start_cycle||last_response_cycle<last_write_cycle)$fatal(1,"completion ordering");
`endif
      read_word(32'ha0000014,observed);
      if(observed!==expected[0])$fatal(1,"CPU result readback mismatch");
      checked=0;
      for(integer s=0;s<64;s=s+1)begin
        for(integer i=0;i<256;i=i+1)begin
          read_word(YBASE+4*(256*s+i),observed);
          if(i<groups[s])begin
            if(observed!==expected[256*s+i])$fatal(1,"CPU matrix mismatch layer=%0d slot=%0d word=%0d got=%h expected=%h",layer,s,i,observed,expected[256*s+i]);
            checked=checked+1;
          end else if(observed!==32'h5a5aa5a5)$fatal(1,"output padding overwritten");
        end
      end
      all_checked=all_checked+checked;
      $display("SOC_MATRIX_PASS layer=%0d checked_words=%0d elapsed_cycles=%0d",layer,checked,cycles-start_cycle);
    end
    boot_monitor=0;
    for(integer i=0;i<32;i=i+1)store_word(32'ha0000000+4*i,0);
    boot_rom_first=0;boot_rom_jump=0;boot_itcm_first=0;
    boot_from_rom();
    $display("SOC_EXECUTION_ALL_PASS tasks=12 checked_words=%0d boots=2",all_checked);
    $finish;
  end
  initial begin #150000000;$fatal(1,"SOC_EXECUTION_TIMEOUT cycles=%0d reset=%b",cycles,rst_n);end
endmodule
