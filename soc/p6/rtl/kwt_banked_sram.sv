// 使用官方宏构成同步单口 SRAM，按字节写入，读数据保持至下一次读操作。
module kwt_banked_sram #(
    parameter integer DW = 32,
    parameter integer AW = 16
) (
    input wire clk, rst_n, cs, we,
    input wire [AW-1:0] addr,
    input wire [DW-1:0] din,
    input wire [DW/8-1:0] wem,
    output wire [DW-1:0] dout
);
    localparam integer ROW_AW = DW == 32 ? 13 : 12;
    localparam integer BANK_AW = AW - ROW_AW;
    localparam integer BANKS = 1 << BANK_AW;
    wire [DW-1:0] bank_q [0:BANKS-1];
    wire [DW-1:0] wen_n;
    reg [BANK_AW-1:0] read_bank;

    generate
        if ((DW != 32 && DW != 64) || BANK_AW < 1) begin : unsupported
            KWT_UNSUPPORTED_PLATFORM_SRAM invalid_configuration();
        end
        for (genvar b = 0; b < DW/8; b = b + 1) begin : byte_mask
            assign wen_n[b*8 +: 8] = {8{~wem[b]}};
        end
        for (genvar b = 0; b < BANKS; b = b + 1) begin : bank
            wire cen_n = ~(cs && addr[AW-1:ROW_AW] == b);
            if (DW == 32) begin : word32
                RAMSP8KX32 ram (
                    .CLK(clk), .CEN(cen_n), .GWEN(~we), .WEN(wen_n),
                    .A(addr[ROW_AW-1:0]), .D(din), .Q(bank_q[b]),
                    .EMA(3'd2), .EMAW(2'd0), .RET1N(1'b1)
                );
            end else begin : word64
                RAMSP4KX64 ram (
                    .CLK(clk), .CEN(cen_n), .GWEN(~we), .WEN(wen_n),
                    .A(addr[ROW_AW-1:0]), .D(din), .Q(bank_q[b]),
                    .EMA(3'd2), .EMAW(2'd0), .RET1N(1'b1)
                );
            end
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) read_bank <= {BANK_AW{1'b0}};
        else if (cs && !we) read_bank <= addr[AW-1:ROW_AW];
    end
    assign dout = bank_q[read_bank];
endmodule
