// 与公共平台的原语接口兼容，门控和时钟选择使用实际 HVT 单元。
module GENERIC_CLOCKGATE_RVT(output ECK, input E, SE, CK);
    CLKLANAQV4_12TH40 u_gate(.CK(CK), .E(E), .TE(SE), .Q(ECK));
endmodule
module GENERIC_CLKMX2_RVT(output Y, input S0, A, B);
    CLKMUX2V4_12TH40 u_mux(.I0(A), .I1(B), .S(S0), .Z(Y));
endmodule
module GENERIC_CLKMX4_RVT(output Y, input S0, S1, A, B, C, D);
    wire ab, cd;
    GENERIC_CLKMX2_RVT m0(ab,S0,A,B), m1(cd,S0,C,D), m2(Y,S1,ab,cd);
endmodule
module GENERIC_CLKMX8_RVT(output Y, input S0, S1, S2, A, B, C, D, E, F, G, H);
    wire abcd, efgh;
    GENERIC_CLKMX4_RVT m0(abcd,S0,S1,A,B,C,D), m1(efgh,S0,S1,E,F,G,H);
    GENERIC_CLKMX2_RVT m2(Y,S2,abcd,efgh);
endmodule
module GENERIC_BUF_RVT(output Y, input A); assign Y=A; endmodule
module GENERIC_CLKBUF_RVT(output Y, input A); assign Y=A; endmodule
module GENERIC_CLKAND2_RVT(output Y, input A,B); assign Y=A&B; endmodule
module GENERIC_CLKNAND2_RVT(output Y, input A,B); assign Y=~(A&B); endmodule
module GENERIC_CLKINV_RVT(output Y, input A); assign Y=~A; endmodule
module GENERIC_CLKOR2_RVT(output Y, input A,B); assign Y=A|B; endmodule
module GENERIC_CLKXOR2_RVT(output Y, input A0,A1); assign Y=A0^A1; endmodule
module GENERIC_INV_RVT(output Y, input A); assign Y=~A; endmodule
module GENERIC_NAND2_RVT(output Y, input A,B); assign Y=~(A&B); endmodule
module GENERIC_NOR2_RVT(output Y, input A,B); assign Y=~(A|B); endmodule
module GENERIC_OR2_RVT(output Y, input A,B); assign Y=A|B; endmodule
