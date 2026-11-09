// SPDX-License-Identifier: Apache-2.0
// E203 SRAM 接口适配：完整请求先寄存，再在下降沿驱动 SRAM。
// CPU 的指令、仲裁和地址分配不变；返回队列保留访问来源与数据。
module sirv_sram_icb_ctrl #(
    parameter DW=32, MW=4, AW=32, AW_LSB=3, USR_W=3
) (
    output wire sram_ctrl_active,
    input wire tcm_cgstop,
    input wire i_icb_cmd_valid,
    output wire i_icb_cmd_ready,
    input wire i_icb_cmd_read,
    input wire [AW-1:0] i_icb_cmd_addr,
    input wire [DW-1:0] i_icb_cmd_wdata,
    input wire [MW-1:0] i_icb_cmd_wmask,
    input wire [USR_W-1:0] i_icb_cmd_usr,
    output wire i_icb_rsp_valid,
    input wire i_icb_rsp_ready,
    output wire [DW-1:0] i_icb_rsp_rdata,
    output wire [USR_W-1:0] i_icb_rsp_usr,
    output reg ram_cs, ram_we,
    output reg [AW-AW_LSB-1:0] ram_addr,
    output reg [MW-1:0] ram_wem,
    output reg [DW-1:0] ram_din,
    input wire [DW-1:0] ram_dout,
    output wire clk_ram,
    input wire test_mode, clk, rst_n
);
    reg [1:0] outstanding;
    reg request_valid, response_due;
    reg request_read, response_read;
    reg [AW-AW_LSB-1:0] request_address;
    reg [DW-1:0] request_data;
    reg [MW-1:0] request_mask;
    reg [USR_W-1:0] request_user, response_user;
    wire accept=i_icb_cmd_valid && i_icb_cmd_ready;
    wire retire=i_icb_rsp_valid && i_icb_rsp_ready;
    wire queue_ready;
    wire [DW+USR_W-1:0] queue_data;
    reg [DW-1:0] last_response;

    // 总额度覆盖请求寄存级、SRAM 读取级以及返回队列。
    assign i_icb_cmd_ready=rst_n && outstanding<2;
    assign sram_ctrl_active=i_icb_cmd_valid || outstanding!=0;
    assign {i_icb_rsp_usr,i_icb_rsp_rdata}=
        i_icb_rsp_valid ? queue_data : {{USR_W{1'b0}},last_response};

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            outstanding<=0;
            request_valid<=0;
            response_due<=0;
        end else begin
            case({accept,retire})
                2'b10: outstanding<=outstanding+1'b1;
                2'b01: outstanding<=outstanding-1'b1;
                default: outstanding<=outstanding;
            endcase
            request_valid<=accept;
            response_due<=request_valid;
        end
    end
    always @(posedge clk) begin
        if(accept) begin
            request_read<=i_icb_cmd_read;
            request_address<=i_icb_cmd_addr[AW-1:AW_LSB];
            request_data<=i_icb_cmd_wdata;
            request_mask<=i_icb_cmd_wmask;
            request_user<=i_icb_cmd_usr;
        end
        if(request_valid) begin
            response_read<=request_read;
            response_user<=request_user;
        end
        if(retire) last_response<=i_icb_rsp_rdata;
    end
    always @(negedge clk or negedge rst_n) begin
        if(!rst_n) begin ram_cs<=0;ram_we<=0;end
        else begin ram_cs<=request_valid;ram_we<=request_valid && !request_read;end
    end
    always @(negedge clk) begin
        if(rst_n && request_valid) begin
            ram_addr<=request_address;
            ram_din<=request_data;
            ram_wem<=request_mask;
        end
    end

    // 门控使能来自上升沿请求寄存器，保留原有调试与停止门控控制。
    e203_clkgate u_ram_clkgate(
        .clk_in(clk),.test_mode(test_mode),
        .clock_en(request_valid || tcm_cgstop),.clk_out(clk_ram));
    sirv_gnrl_fifo #(.DP(2),.DW(DW+USR_W),.CUT_READY(1),.MSKO(0)) u_responses(
        .i_vld(response_due),.i_rdy(queue_ready),
        .i_dat({response_user,response_read ? ram_dout : {DW{1'b0}}}),
        .o_vld(i_icb_rsp_valid),.o_rdy(i_icb_rsp_ready),.o_dat(queue_data),
        .clk(clk),.rst_n(rst_n));
`ifndef SYNTHESIS
    always @(posedge clk) if(rst_n) begin
        if(response_due && !queue_ready) $fatal(1,"SRAM_RESPONSE_QUEUE_OVERFLOW");
        if(retire && outstanding==0) $fatal(1,"SRAM_RESPONSE_WITHOUT_REQUEST");
        if(outstanding>2) $fatal(1,"SRAM_OUTSTANDING_OVERFLOW");
    end
`endif
endmodule
