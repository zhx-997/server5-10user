module sram_wrap_64KX32 #(
    parameter ADDRWIDTH = 16,
    parameter DATAWIDTH = 32
) (
    input CLK, RSTN,
    input [ADDRWIDTH-1:0] ADDRESS,
    input CS, WE,
    input [3:0] WEM,
    input [DATAWIDTH-1:0] WDATA,
    output [DATAWIDTH-1:0] RDATA
);
    kwt_banked_sram #(.AW(ADDRWIDTH), .DW(DATAWIDTH)) u_banks (
        .clk(CLK), .rst_n(RSTN), .cs(CS), .we(WE),
        .addr(ADDRESS), .din(WDATA), .wem(WEM), .dout(RDATA)
    );
endmodule
