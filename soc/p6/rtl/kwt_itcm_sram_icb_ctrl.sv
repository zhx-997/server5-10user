module kwt_itcm_sram_icb_ctrl #(
    parameter DW = 64,
    parameter MW = 8,
    parameter AW = 18,
    parameter AW_LSB = 3,
    parameter USR_W = 2
)(
    output sram_ctrl_active,
    input tcm_cgstop,
    input i_icb_cmd_valid,
    output i_icb_cmd_ready,
    input i_icb_cmd_read,
    input [AW-1:0] i_icb_cmd_addr,
    input [DW-1:0] i_icb_cmd_wdata,
    input [MW-1:0] i_icb_cmd_wmask,
    input [USR_W-1:0] i_icb_cmd_usr,
    output i_icb_rsp_valid,
    input i_icb_rsp_ready,
    output [DW-1:0] i_icb_rsp_rdata,
    output [USR_W-1:0] i_icb_rsp_usr,
    output ram_cs,
    output ram_we,
    output [AW-AW_LSB-1:0] ram_addr,
    output [MW-1:0] ram_wem,
    output [DW-1:0] ram_din,
    input [DW-1:0] ram_dout,
    output clk_ram,
    input test_mode,
    input clk,
    input rst_n
);
    wire inner_active;
    wire raw_rsp_valid;
    wire raw_rsp_ready;
    wire [DW-1:0] raw_rsp_rdata;
    wire [USR_W-1:0] raw_rsp_usr;

    sirv_sram_icb_ctrl #(
        .DW(DW), .MW(MW), .AW(AW), .AW_LSB(AW_LSB), .USR_W(USR_W)
    ) u_native_ctrl (
        .sram_ctrl_active(inner_active), .tcm_cgstop(tcm_cgstop),
        .i_icb_cmd_valid(i_icb_cmd_valid), .i_icb_cmd_ready(i_icb_cmd_ready),
        .i_icb_cmd_read(i_icb_cmd_read), .i_icb_cmd_addr(i_icb_cmd_addr),
        .i_icb_cmd_wdata(i_icb_cmd_wdata), .i_icb_cmd_wmask(i_icb_cmd_wmask),
        .i_icb_cmd_usr(i_icb_cmd_usr),
        .i_icb_rsp_valid(raw_rsp_valid), .i_icb_rsp_ready(raw_rsp_ready),
        .i_icb_rsp_rdata(raw_rsp_rdata), .i_icb_rsp_usr(raw_rsp_usr),
        .ram_cs(ram_cs), .ram_we(ram_we), .ram_addr(ram_addr),
        .ram_wem(ram_wem), .ram_din(ram_din), .ram_dout(ram_dout),
        .clk_ram(clk_ram), .test_mode(test_mode), .clk(clk), .rst_n(rst_n)
    );

    // 数据与访问来源共用一次握手，暂停时保持稳定。
    sirv_gnrl_pipe_stage #(
        .DP(1), .CUT_READY(1), .DW(DW + USR_W)
    ) u_response_stage (
        .i_vld(raw_rsp_valid), .i_rdy(raw_rsp_ready),
        .i_dat({raw_rsp_usr, raw_rsp_rdata}),
        .o_vld(i_icb_rsp_valid), .o_rdy(i_icb_rsp_ready),
        .o_dat({i_icb_rsp_usr, i_icb_rsp_rdata}),
        .clk(clk), .rst_n(rst_n)
    );

    // 响应尚未被接收时，控制器时钟必须继续工作。
    assign sram_ctrl_active = inner_active | i_icb_rsp_valid;
endmodule
