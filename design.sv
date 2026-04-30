module apb_slave (
    input  wire        PCLK,
    input  wire        PRESETn,
    input  wire        PSEL,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [7:0]  PADDR,
    input  wire [31:0] PWDATA,
    output reg  [31:0] PRDATA,
    output wire        PREADY
);

    reg [31:0] regs [0:3];

    assign PREADY = 1'b1;

    integer i;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            for (i = 0; i < 4; i = i + 1)
                regs[i] <= 32'h0;
        end else begin
            if (PSEL && PENABLE && PWRITE) begin
                regs[PADDR[3:2]] <= PWDATA;
            end
        end
    end

    // combinational read - no clock delay
    always @(*) begin
        if (PSEL && !PWRITE)
            PRDATA = regs[PADDR[3:2]];
        else
            PRDATA = 32'h0;
    end

endmodule
