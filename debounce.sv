module debounce (
    input  logic clk,        // 50 МГц
    input  logic rst_n,      
    input  logic in_raw,     // Сигнал з матриці або кнопки
    output logic out_clean   // Стабільний сигнал
);
    // 20 мс при 50 МГц = 1,000,000 тактів
    localparam CTR_MAX = 20'd1000000;
    reg [19:0] counter;
    reg        sync_0, sync_1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_0    <= 1'b0;
            sync_1    <= 1'b0;
            counter   <= '0;
            out_clean <= 1'b0;
        end else begin
            sync_0 <= in_raw; // Захист від метастабільності
            sync_1 <= sync_0;

            if (sync_1 != out_clean) begin
                counter <= counter + 1'b1;
                if (counter >= CTR_MAX) begin
                    out_clean <= sync_1;
                    counter   <= '0;
                end
            end else begin
                counter <= '0;
            end
        end
    end
endmodule
