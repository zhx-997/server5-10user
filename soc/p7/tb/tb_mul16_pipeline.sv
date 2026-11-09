`timescale 1ns/1ps
module tb_mul16_pipeline;
    reg clk=0,rst_n=0,clear=0,in_valid=0,in_last=0;
    reg signed [15:0] in_x=0,in_w=0;
    wire out_valid,out_last;
    wire signed [31:0] out_product;
    kwt_mul16_pipe dut(.*);
    always #3.333333333 clk=~clk;
    reg signed [31:0] expected[0:20000];
    reg expected_last[0:20000];
    integer head=0,tail=0,checked=0,aborted=0;
    reg signed [15:0] edges[0:7];
    integer seed=203,random_value;
    always @(posedge clk)begin
        if(!rst_n||clear)begin aborted=aborted+tail-head;head=0;tail=0;end
        else begin
            if(out_valid)begin
                if(head==tail||out_product!==expected[head]||out_last!==expected_last[head])
                    $fatal(1,"MULTIPLY_MISMATCH index=%0d got=%h expected=%h",head,out_product,expected[head]);
                head=head+1;checked=checked+1;
            end
            if(in_valid)begin
                expected[tail]=$signed(in_x)*$signed(in_w);
                expected_last[tail]=in_last;
                tail=tail+1;
            end
        end
    end
    task automatic send(input signed [15:0] x,w,input tag);
        begin @(negedge clk);in_valid=1;in_x=x;in_w=w;in_last=tag;end
    endtask
    initial begin
        edges[0]=-32768;edges[1]=-32767;edges[2]=-256;edges[3]=-1;
        edges[4]=0;edges[5]=1;edges[6]=255;edges[7]=32767;
        repeat(4)@(negedge clk);rst_n=1;
        for(integer a=0;a<8;a=a+1)
            for(integer b=0;b<8;b=b+1)send(edges[a],edges[b],b==7);
        for(integer n=0;n<16384;n=n+1)begin
            random_value=$random(seed);send(random_value[15:0],random_value[31:16],n%64==63);
            if(n%31==7)begin @(negedge clk);in_valid=0;end
        end
        @(negedge clk);in_valid=0;repeat(8)@(negedge clk);
        if(head!=tail||checked!=16448)$fatal(1,"MULTIPLY_MISSING_RESULT");
        send(17,-29,1);send(-32768,32767,0);
        @(negedge clk);clear=1;in_valid=0;
        @(negedge clk);clear=0;repeat(8)@(negedge clk);
        if(head!=tail||aborted!=2)$fatal(1,"MULTIPLY_CLEAR_FAILED");
        send(-17,-19,1);@(negedge clk);in_valid=0;repeat(8)@(negedge clk);
        if(checked!=16449)$fatal(1,"MULTIPLY_RESTART_FAILED");
        $display("MULTIPLY_PIPELINE_PASS checked=%0d aborted=%0d",checked,aborted);$finish;
    end
    initial begin #1000000;$fatal(1,"MULTIPLY_TIMEOUT");end
endmodule
