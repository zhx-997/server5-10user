 /*                                                                      
 Copyright 2018-2020 Nuclei System Technology, Inc.                
                                                                         
 Licensed under the Apache License, Version 2.0 (the "License");         
 you may not use this file except in compliance with the License.        
 You may obtain a copy of the License at                                 
                                                                         
     http://www.apache.org/licenses/LICENSE-2.0                          
                                                                         
  Unless required by applicable law or agreed to in writing, software    
 distributed under the License is distributed on an "AS IS" BASIS,       
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and     
 limitations under the License.                                          
 */                                                                      
                                                                         
                                                                         
                                                                         
`include "e203_defines.v"
module kwt_e203_soc_top(
  output sys_clk, sys_rst_n,
  input load_cmd_valid, load_cmd_read,
  output load_cmd_ready,
  input [31:0] load_cmd_addr, load_cmd_wdata,
  input [3:0] load_cmd_wmask,
  output load_rsp_valid, load_rsp_err,
  input load_rsp_ready,
  output [31:0] load_rsp_rdata,
  input itcm_cmd_valid, itcm_cmd_read,
  output itcm_cmd_ready,
  input [17:0] itcm_cmd_addr,
  input [31:0] itcm_cmd_wdata,
  input [3:0] itcm_cmd_wmask,
  output itcm_rsp_valid, itcm_rsp_err,
  input itcm_rsp_ready,
  output [31:0] itcm_rsp_rdata,

    // This clock should comes from the crystal pad generated high speed clock (16MHz)
  input  hfextclk,
  output hfxoscen,// The signal to enable the crystal pad generated clock

  // This clock should comes from the crystal pad generated low speed clock (32.768KHz)
  input  lfextclk,
  output lfxoscen,// The signal to enable the crystal pad generated clock


  // The JTAG TCK is input, need to be pull-up
  input   io_pads_jtag_TCK_i_ival,

  // The JTAG TMS is input, need to be pull-up
  input   io_pads_jtag_TMS_i_ival,

  // The JTAG TDI is input, need to be pull-up
  input   io_pads_jtag_TDI_i_ival,

  // The JTAG TDO is output have enable
  output  io_pads_jtag_TDO_o_oval,
  output  io_pads_jtag_TDO_o_oe,

  // The GPIO are all bidir pad have enables
  input  [32-1:0] io_pads_gpioA_i_ival,
  output [32-1:0] io_pads_gpioA_o_oval,
  output [32-1:0] io_pads_gpioA_o_oe,

  input  [32-1:0] io_pads_gpioB_i_ival,
  output [32-1:0] io_pads_gpioB_o_oval,
  output [32-1:0] io_pads_gpioB_o_oe,

  //QSPI0 SCK and CS is output without enable
  output  io_pads_qspi0_sck_o_oval,
  output  io_pads_qspi0_cs_0_o_oval,

  //QSPI0 DQ is bidir I/O with enable, and need pull-up enable
  input   io_pads_qspi0_dq_0_i_ival,
  output  io_pads_qspi0_dq_0_o_oval,
  output  io_pads_qspi0_dq_0_o_oe,
  input   io_pads_qspi0_dq_1_i_ival,
  output  io_pads_qspi0_dq_1_o_oval,
  output  io_pads_qspi0_dq_1_o_oe,
  input   io_pads_qspi0_dq_2_i_ival,
  output  io_pads_qspi0_dq_2_o_oval,
  output  io_pads_qspi0_dq_2_o_oe,
  input   io_pads_qspi0_dq_3_i_ival,
  output  io_pads_qspi0_dq_3_o_oval,
  output  io_pads_qspi0_dq_3_o_oe,
  
  // Erst is input need to be pull-up by default
  input   io_pads_aon_erst_n_i_ival,

  // dbgmode are inputs need to be pull-up by default
  input  io_pads_dbgmode0_n_i_ival,
  input  io_pads_dbgmode1_n_i_ival,
  input  io_pads_dbgmode2_n_i_ival,

  // BootRom is input need to be pull-up by default
  input  io_pads_bootrom_n_i_ival,


  // dwakeup is input need to be pull-up by default
  input  io_pads_aon_pmu_dwakeup_n_i_ival,

      // PMU output is just output without enable
  output io_pads_aon_pmu_padrst_o_oval,
  output io_pads_aon_pmu_vddpaden_o_oval 
);


 
 wire sysper_icb_cmd_valid;
 wire sysper_icb_cmd_ready;

 wire sysfio_icb_cmd_valid;
 wire sysfio_icb_cmd_ready;

 wire sysmem_icb_cmd_valid;
 wire sysmem_icb_cmd_ready;
 wire [31:0] sysmem_icb_cmd_addr, sysmem_icb_cmd_wdata;
 wire [3:0] sysmem_icb_cmd_wmask;
 wire sysmem_icb_cmd_read;
 wire sysmem_icb_rsp_valid, sysmem_icb_rsp_ready, sysmem_icb_rsp_err;
 wire [31:0] sysmem_icb_rsp_rdata;
 wire soc_corerst;
 reg [1:0] shared_reset_sync;
 always @(posedge sys_clk or posedge soc_corerst) begin
   if (soc_corerst) shared_reset_sync <= 2'b00;
   else shared_reset_sync <= {shared_reset_sync[0], 1'b1};
 end
 assign sys_rst_n = shared_reset_sync[1];

 wire mem_cmd_valid, mem_cmd_ready, mem_cmd_read;
 wire [31:0] mem_cmd_addr, mem_cmd_wdata, mem_rsp_rdata;
 wire [3:0] mem_cmd_wmask;
 wire mem_rsp_valid, mem_rsp_ready, mem_rsp_err;
 sirv_gnrl_icb_arbt #(.AW(32), .DW(32), .USR_W(1), .ARBT_NUM(2),
   .ARBT_PTR_W(1), .FIFO_OUTS_NUM(1), .ALLOW_0CYCL_RSP(0)) u_shared_arbiter (
   .i_bus_icb_cmd_valid({load_cmd_valid,sysmem_icb_cmd_valid}),
   .i_bus_icb_cmd_ready({load_cmd_ready,sysmem_icb_cmd_ready}),
   .i_bus_icb_cmd_read({load_cmd_read,sysmem_icb_cmd_read}),
   .i_bus_icb_cmd_addr({load_cmd_addr,sysmem_icb_cmd_addr}),
   .i_bus_icb_cmd_wdata({load_cmd_wdata,sysmem_icb_cmd_wdata}),
   .i_bus_icb_cmd_wmask({load_cmd_wmask,sysmem_icb_cmd_wmask}),
   .i_bus_icb_cmd_burst(4'b0), .i_bus_icb_cmd_beat(4'b0),
   .i_bus_icb_cmd_lock(2'b0), .i_bus_icb_cmd_excl(2'b0),
   .i_bus_icb_cmd_size(4'b1010), .i_bus_icb_cmd_usr(2'b0),
   .i_bus_icb_rsp_valid({load_rsp_valid,sysmem_icb_rsp_valid}),
   .i_bus_icb_rsp_ready({load_rsp_ready,sysmem_icb_rsp_ready}),
   .i_bus_icb_rsp_err({load_rsp_err,sysmem_icb_rsp_err}),
   .i_bus_icb_rsp_rdata({load_rsp_rdata,sysmem_icb_rsp_rdata}),
   .i_bus_icb_rsp_excl_ok(), .i_bus_icb_rsp_usr(),
   .o_icb_cmd_valid(mem_cmd_valid), .o_icb_cmd_ready(mem_cmd_ready),
   .o_icb_cmd_read(mem_cmd_read), .o_icb_cmd_addr(mem_cmd_addr),
   .o_icb_cmd_wdata(mem_cmd_wdata), .o_icb_cmd_wmask(mem_cmd_wmask),
   .o_icb_cmd_burst(), .o_icb_cmd_beat(), .o_icb_cmd_lock(),
   .o_icb_cmd_excl(), .o_icb_cmd_size(), .o_icb_cmd_usr(),
   .o_icb_rsp_valid(mem_rsp_valid), .o_icb_rsp_ready(mem_rsp_ready),
   .o_icb_rsp_err(mem_rsp_err), .o_icb_rsp_excl_ok(1'b0),
   .o_icb_rsp_rdata(mem_rsp_rdata), .o_icb_rsp_usr(1'b0),
   .clk(sys_clk), .rst_n(sys_rst_n)
 );
 kwt_shared_sram u_shared_sram (
   .clk(sys_clk), .rst_n(sys_rst_n),
   .cmd_valid(mem_cmd_valid), .cmd_ready(mem_cmd_ready),
   .cmd_read(mem_cmd_read), .cmd_addr(mem_cmd_addr),
   .cmd_wdata(mem_cmd_wdata), .cmd_wmask(mem_cmd_wmask),
   .rsp_valid(mem_rsp_valid), .rsp_ready(mem_rsp_ready),
   .rsp_rdata(mem_rsp_rdata), .rsp_err(mem_rsp_err)
 );

 e203_subsys_top u_e203_subsys_top(
    .soc_hfclk(sys_clk), .soc_corerst(soc_corerst),
    .core_mhartid      (1'b0),
  



  `ifdef E203_HAS_ITCM_EXTITF //{
    .ext2itcm_icb_cmd_valid  (itcm_cmd_valid),
    .ext2itcm_icb_cmd_ready  (itcm_cmd_ready),
    .ext2itcm_icb_cmd_addr   (itcm_cmd_addr),
    .ext2itcm_icb_cmd_read   (itcm_cmd_read),
    .ext2itcm_icb_cmd_wdata  (itcm_cmd_wdata),
    .ext2itcm_icb_cmd_wmask  (itcm_cmd_wmask),
    
    .ext2itcm_icb_rsp_valid  (itcm_rsp_valid),
    .ext2itcm_icb_rsp_ready  (itcm_rsp_ready),
    .ext2itcm_icb_rsp_err    (itcm_rsp_err),
    .ext2itcm_icb_rsp_rdata  (itcm_rsp_rdata),
  `endif//}

  `ifdef E203_HAS_DTCM_EXTITF //{
    .ext2dtcm_icb_cmd_valid  (1'b0),
    .ext2dtcm_icb_cmd_ready  (),
    .ext2dtcm_icb_cmd_addr   (`E203_DTCM_ADDR_WIDTH'b0 ),
    .ext2dtcm_icb_cmd_read   (1'b0 ),
    .ext2dtcm_icb_cmd_wdata  (32'b0),
    .ext2dtcm_icb_cmd_wmask  (4'b0),
    
    .ext2dtcm_icb_rsp_valid  (),
    .ext2dtcm_icb_rsp_ready  (1'b0),
    .ext2dtcm_icb_rsp_err    (),
    .ext2dtcm_icb_rsp_rdata  (),
  `endif//}

  .sysper_icb_cmd_valid (sysper_icb_cmd_valid),
  .sysper_icb_cmd_ready (sysper_icb_cmd_ready),
  .sysper_icb_cmd_read  (), 
  .sysper_icb_cmd_addr  (), 
  .sysper_icb_cmd_wdata (), 
  .sysper_icb_cmd_wmask (), 
  
  .sysper_icb_rsp_valid (sysper_icb_cmd_valid),
  .sysper_icb_rsp_ready (sysper_icb_cmd_ready),
  .sysper_icb_rsp_err   (1'b0  ),
  .sysper_icb_rsp_rdata (32'b0),


  .sysfio_icb_cmd_valid(sysfio_icb_cmd_valid),
  .sysfio_icb_cmd_ready(sysfio_icb_cmd_ready),
  .sysfio_icb_cmd_read (), 
  .sysfio_icb_cmd_addr (), 
  .sysfio_icb_cmd_wdata(), 
  .sysfio_icb_cmd_wmask(), 
   
  .sysfio_icb_rsp_valid(sysfio_icb_cmd_valid),
  .sysfio_icb_rsp_ready(sysfio_icb_cmd_ready),
  .sysfio_icb_rsp_err  (1'b0  ),
  .sysfio_icb_rsp_rdata(32'b0),

  .sysmem_icb_cmd_valid(sysmem_icb_cmd_valid),
  .sysmem_icb_cmd_ready(sysmem_icb_cmd_ready),
  .sysmem_icb_cmd_read (sysmem_icb_cmd_read),
  .sysmem_icb_cmd_addr (sysmem_icb_cmd_addr),
  .sysmem_icb_cmd_wdata(sysmem_icb_cmd_wdata),
  .sysmem_icb_cmd_wmask(sysmem_icb_cmd_wmask),

  .sysmem_icb_rsp_valid(sysmem_icb_rsp_valid),
  .sysmem_icb_rsp_ready(sysmem_icb_rsp_ready),
  .sysmem_icb_rsp_err  (sysmem_icb_rsp_err),
  .sysmem_icb_rsp_rdata(sysmem_icb_rsp_rdata),

  .io_pads_jtag_TCK_i_ival    (io_pads_jtag_TCK_i_ival    ),
  .io_pads_jtag_TCK_o_oval    (),
  .io_pads_jtag_TCK_o_oe      (),
  .io_pads_jtag_TCK_o_ie      (),
  .io_pads_jtag_TCK_o_pue     (),
  .io_pads_jtag_TCK_o_ds      (),

  .io_pads_jtag_TMS_i_ival    (io_pads_jtag_TMS_i_ival    ),
  .io_pads_jtag_TMS_o_oval    (),
  .io_pads_jtag_TMS_o_oe      (),
  .io_pads_jtag_TMS_o_ie      (),
  .io_pads_jtag_TMS_o_pue     (),
  .io_pads_jtag_TMS_o_ds      (),

  .io_pads_jtag_TDI_i_ival    (io_pads_jtag_TDI_i_ival    ),
  .io_pads_jtag_TDI_o_oval    (),
  .io_pads_jtag_TDI_o_oe      (),
  .io_pads_jtag_TDI_o_ie      (),
  .io_pads_jtag_TDI_o_pue     (),
  .io_pads_jtag_TDI_o_ds      (),

  .io_pads_jtag_TDO_i_ival    (1'b1    ),
  .io_pads_jtag_TDO_o_oval    (io_pads_jtag_TDO_o_oval    ),
  .io_pads_jtag_TDO_o_oe      (io_pads_jtag_TDO_o_oe      ),
  .io_pads_jtag_TDO_o_ie      (),
  .io_pads_jtag_TDO_o_pue     (),
  .io_pads_jtag_TDO_o_ds      (),

  .io_pads_jtag_TRST_n_i_ival (1'b1 ),
  .io_pads_jtag_TRST_n_o_oval (),
  .io_pads_jtag_TRST_n_o_oe   (),
  .io_pads_jtag_TRST_n_o_ie   (),
  .io_pads_jtag_TRST_n_o_pue  (),
  .io_pads_jtag_TRST_n_o_ds   (),

  .test_mode(1'b0),
  .test_iso_override(1'b0),

  .io_pads_gpioA_i_ival       (io_pads_gpioA_i_ival),
  .io_pads_gpioA_o_oval       (io_pads_gpioA_o_oval),
  .io_pads_gpioA_o_oe         (io_pads_gpioA_o_oe), 

  .io_pads_gpioB_i_ival       (io_pads_gpioB_i_ival),
  .io_pads_gpioB_o_oval       (io_pads_gpioB_o_oval),
  .io_pads_gpioB_o_oe         (io_pads_gpioB_o_oe), 

  .io_pads_qspi0_sck_i_ival   (1'b1),
  .io_pads_qspi0_sck_o_oval   (io_pads_qspi0_sck_o_oval),
  .io_pads_qspi0_sck_o_oe     (),
  .io_pads_qspi0_dq_0_i_ival  (io_pads_qspi0_dq_0_i_ival),
  .io_pads_qspi0_dq_0_o_oval  (io_pads_qspi0_dq_0_o_oval),
  .io_pads_qspi0_dq_0_o_oe    (io_pads_qspi0_dq_0_o_oe),
  .io_pads_qspi0_dq_1_i_ival  (io_pads_qspi0_dq_1_i_ival),
  .io_pads_qspi0_dq_1_o_oval  (io_pads_qspi0_dq_1_o_oval),
  .io_pads_qspi0_dq_1_o_oe    (io_pads_qspi0_dq_1_o_oe),
  .io_pads_qspi0_dq_2_i_ival  (io_pads_qspi0_dq_2_i_ival),
  .io_pads_qspi0_dq_2_o_oval  (io_pads_qspi0_dq_2_o_oval),
  .io_pads_qspi0_dq_2_o_oe    (io_pads_qspi0_dq_2_o_oe),
  .io_pads_qspi0_dq_3_i_ival  (io_pads_qspi0_dq_3_i_ival),
  .io_pads_qspi0_dq_3_o_oval  (io_pads_qspi0_dq_3_o_oval),
  .io_pads_qspi0_dq_3_o_oe    (io_pads_qspi0_dq_3_o_oe),
  .io_pads_qspi0_cs_0_i_ival  (1'b1),
  .io_pads_qspi0_cs_0_o_oval  (io_pads_qspi0_cs_0_o_oval),
  .io_pads_qspi0_cs_0_o_oe    (), 

    .hfextclk        (hfextclk),
    .hfxoscen        (hfxoscen),
    .lfextclk        (lfextclk),
    .lfxoscen        (lfxoscen),

  .io_pads_aon_erst_n_i_ival        (io_pads_aon_erst_n_i_ival       ), 
  .io_pads_aon_erst_n_o_oval        (),
  .io_pads_aon_erst_n_o_oe          (),
  .io_pads_aon_erst_n_o_ie          (),
  .io_pads_aon_erst_n_o_pue         (),
  .io_pads_aon_erst_n_o_ds          (),
  .io_pads_aon_pmu_dwakeup_n_i_ival (io_pads_aon_pmu_dwakeup_n_i_ival),
  .io_pads_aon_pmu_dwakeup_n_o_oval (),
  .io_pads_aon_pmu_dwakeup_n_o_oe   (),
  .io_pads_aon_pmu_dwakeup_n_o_ie   (),
  .io_pads_aon_pmu_dwakeup_n_o_pue  (),
  .io_pads_aon_pmu_dwakeup_n_o_ds   (),
  .io_pads_aon_pmu_vddpaden_i_ival  (1'b1 ),
  .io_pads_aon_pmu_vddpaden_o_oval  (io_pads_aon_pmu_vddpaden_o_oval ),
  .io_pads_aon_pmu_vddpaden_o_oe    (),
  .io_pads_aon_pmu_vddpaden_o_ie    (),
  .io_pads_aon_pmu_vddpaden_o_pue   (),
  .io_pads_aon_pmu_vddpaden_o_ds    (),

  
    .io_pads_aon_pmu_padrst_i_ival    (1'b1 ),
    .io_pads_aon_pmu_padrst_o_oval    (io_pads_aon_pmu_padrst_o_oval ),
    .io_pads_aon_pmu_padrst_o_oe      (),
    .io_pads_aon_pmu_padrst_o_ie      (),
    .io_pads_aon_pmu_padrst_o_pue     (),
    .io_pads_aon_pmu_padrst_o_ds      (),

    .io_pads_bootrom_n_i_ival       (io_pads_bootrom_n_i_ival),
    .io_pads_bootrom_n_o_oval       (),
    .io_pads_bootrom_n_o_oe         (),
    .io_pads_bootrom_n_o_ie         (),
    .io_pads_bootrom_n_o_pue        (),
    .io_pads_bootrom_n_o_ds         (),

    .io_pads_dbgmode0_n_i_ival       (io_pads_dbgmode0_n_i_ival),

    .io_pads_dbgmode1_n_i_ival       (io_pads_dbgmode1_n_i_ival),

    .io_pads_dbgmode2_n_i_ival       (io_pads_dbgmode2_n_i_ival) 


  );


endmodule
