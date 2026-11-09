`timescale 1ns/1ps
module tb_icb_registered;
    reg clk=0,rst_n=0,req_valid=0,ret_ready=0;
    reg [31:0] req_addr=0,req_wdata=0;
    reg req_read=0;
    wire req_ready,ret_valid,ret_err,cmd_valid,cmd_ready,cmd_read,rsp_valid,rsp_ready,rsp_err,idle;
    wire [31:0] ret_rdata,cmd_addr,cmd_wdata,rsp_rdata;
    wire [1:0] cmd_size;
    kwt43_icb_master dut(.*);
    always #3.333333333 clk=~clk;
    reg immediate=0,permit=0,busy=0;
    integer delay_count=0,seed=4099,cycles=0;
    reg [31:0] bus_data;
    reg bus_error;
    wire command=cmd_valid&&cmd_ready;
    wire response=rsp_valid&&rsp_ready;
    assign cmd_ready=rst_n&&permit&&!busy;
    assign rsp_valid=rst_n&&(immediate?command:(busy&&delay_count==0));
    assign rsp_rdata=immediate?(cmd_addr^cmd_wdata^32'h95a371c2):bus_data;
    assign rsp_err=immediate?cmd_addr[4]:bus_error;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin busy<=0;delay_count<=0;end
        else if(!immediate)begin
            if(command)begin
                busy<=1;delay_count<=1+(cmd_addr[7:2]%9);
                bus_data<=cmd_addr^cmd_wdata^32'h95a371c2;
                bus_error<=cmd_addr[4];
            end else if(busy&&delay_count!=0)delay_count<=delay_count-1;
            else if(response)busy<=0;
        end
    end
    reg [31:0] expected_addr,expected_data,expected_return;
    reg expected_read,expected_error,pending=0,sent=0;
    reg stalled_command=0,stalled_return=0;
    reg [64:0] saved_command;
    reg [32:0] saved_return;
    integer accepted=0,issued=0,completed=0,aborted=0,command_stalls=0,return_stalls=0;
    integer zero_responses=0,delayed_responses=0;
    always @(posedge clk)begin
        cycles=cycles+1;
        if(!rst_n)begin
            if(pending)aborted=aborted+1;
            pending=0;sent=0;stalled_command=0;stalled_return=0;
        end else begin
            if(stalled_command && (!cmd_valid || {cmd_read,cmd_addr,cmd_wdata}!==saved_command))
                $fatal(1,"ICB_STALLED_COMMAND_CHANGED");
            if(stalled_return && (!ret_valid || {ret_err,ret_rdata}!==saved_return))
                $fatal(1,"ICB_STALLED_RETURN_CHANGED");
            stalled_command=cmd_valid&&!cmd_ready;
            stalled_return=ret_valid&&!ret_ready;
            saved_command={cmd_read,cmd_addr,cmd_wdata};saved_return={ret_err,ret_rdata};
            if(stalled_command)command_stalls=command_stalls+1;
            if(stalled_return)return_stalls=return_stalls+1;
            if(req_valid&&req_ready)begin
                if(pending)$fatal(1,"ICB_SECOND_REQUEST_ACCEPTED");
                pending=1;sent=0;accepted=accepted+1;
                expected_addr=req_addr;expected_data=req_wdata;expected_read=req_read;
                expected_return=req_addr^req_wdata^32'h95a371c2;expected_error=req_addr[4];
            end
            if(command)begin
                if(!pending||sent||cmd_addr!==expected_addr||cmd_wdata!==expected_data||cmd_read!==expected_read||cmd_size!==2'b10)
                    $fatal(1,"ICB_COMMAND_MISMATCH");
                sent=1;issued=issued+1;
            end
            if(response)begin
                if(immediate)zero_responses=zero_responses+1;else delayed_responses=delayed_responses+1;
            end
            if(ret_valid&&ret_ready)begin
                if(!pending||!sent||ret_rdata!==expected_return||ret_err!==expected_error)
                    $fatal(1,"ICB_RETURN_MISMATCH");
                pending=0;completed=completed+1;
            end
        end
    end
    task automatic transfer(input integer index);
        integer started;
        begin
            @(negedge clk);req_valid=1;req_addr=32'ha0000000+4*index;
            req_wdata=$random(seed);req_read=index[0];started=cycles;
            do @(posedge clk);while(!req_ready);
            @(negedge clk);req_valid=0;req_addr=32'hffffffff;req_wdata=32'hdeadbeef;req_read=~req_read;
            while(pending)begin
                permit=($random(seed)&7)!=0;ret_ready=($random(seed)&3)==0;
                @(negedge clk);
                if(cycles-started>200)$fatal(1,"ICB_TRANSFER_TIMEOUT");
            end
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(integer mode=0;mode<2;mode=mode+1)begin
            immediate=mode==0;
            for(integer n=0;n<1000;n=n+1)transfer(n);
        end
        // 已接收但尚未发出的请求遇到复位，不能在释放后重新发送。
        @(negedge clk);permit=0;ret_ready=0;req_valid=1;req_addr=32'ha0010000;req_wdata=7;
        @(posedge clk);@(negedge clk);req_valid=0;
        repeat(3)@(negedge clk);rst_n=0;
        repeat(3)@(negedge clk);rst_n=1;permit=1;ret_ready=1;
        repeat(12)@(negedge clk);
        if(cmd_valid||ret_valid||!idle||busy)$fatal(1,"ICB_RESET_NOT_EMPTY");
        // 已返回但被消费者暂停的响应遇到复位，必须撤销。
        immediate=0;ret_ready=0;req_valid=1;req_addr=32'ha0000020;req_wdata=9;
        @(posedge clk);@(negedge clk);req_valid=0;
        while(!ret_valid)@(negedge clk);
        rst_n=0;repeat(3)@(negedge clk);rst_n=1;ret_ready=1;
        repeat(12)@(negedge clk);
        if(cmd_valid||ret_valid||!idle||busy)$fatal(1,"ICB_RESET_REPLAYED_RESPONSE");
        if(accepted!=completed+aborted||completed!=2000||aborted!=2||zero_responses!=1000||delayed_responses!=1001||command_stalls<10||return_stalls<10)
            $fatal(1,"ICB_COVERAGE_FAILED accepted=%0d completed=%0d aborted=%0d",accepted,completed,aborted);
        $display("ICB_REGISTERED_PASS completed=%0d aborted=%0d zero=%0d delayed=%0d",completed,aborted,zero_responses,delayed_responses);$finish;
    end
    initial begin #1000000;$fatal(1,"ICB_TEST_TIMEOUT");end
endmodule
