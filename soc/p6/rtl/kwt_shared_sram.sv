// sysmem 端口的 512 KiB 存储器，地址范围由本工程固定。
module kwt_shared_sram (
    input wire clk, rst_n,
    input wire cmd_valid, cmd_read,
    output wire cmd_ready,
    input wire [31:0] cmd_addr, cmd_wdata,
    input wire [3:0] cmd_wmask,
    output wire rsp_valid, rsp_err,
    input wire rsp_ready,
    output wire [31:0] rsp_rdata
);
    wire ram_cs, ram_we, ram_clk;
    wire [29:0] ram_addr;
    wire [3:0] ram_wem;
    wire [31:0] ram_din, ram_dout;
    wire bad_addr = cmd_addr[31:19] != (32'hA0000000 >> 19);
    wire ram_in_range = ram_addr[29:17] == (32'hA0000000 >> 19);
    sirv_sram_icb_ctrl #(.DW(32), .MW(4), .AW(32), .AW_LSB(2), .USR_W(1)) u_ctrl (
        .sram_ctrl_active(), .tcm_cgstop(1'b0),
        .i_icb_cmd_valid(cmd_valid), .i_icb_cmd_ready(cmd_ready),
        .i_icb_cmd_read(cmd_read), .i_icb_cmd_addr(cmd_addr),
        .i_icb_cmd_wdata(cmd_wdata), .i_icb_cmd_wmask(cmd_wmask),
        .i_icb_cmd_usr(bad_addr),
        .i_icb_rsp_valid(rsp_valid), .i_icb_rsp_ready(rsp_ready),
        .i_icb_rsp_rdata(rsp_rdata), .i_icb_rsp_usr(rsp_err),
        .ram_cs(ram_cs), .ram_we(ram_we), .ram_addr(ram_addr),
        .ram_wem(ram_wem), .ram_din(ram_din), .ram_dout(ram_dout),
        .clk_ram(ram_clk), .test_mode(1'b0), .clk(clk), .rst_n(rst_n)
    );
    kwt_banked_sram #(.DW(32), .AW(17)) u_storage (
        .clk(ram_clk), .rst_n(rst_n), .cs(ram_cs && ram_in_range),
        .we(ram_we), .addr(ram_addr[16:0]), .din(ram_din),
        .wem(ram_wem), .dout(ram_dout)
    );
endmodule
