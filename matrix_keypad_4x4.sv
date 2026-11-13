module matrix_keypad_4x4 (
    input  logic        clk,        // 50 МГц
    input  logic        rst_n,      
    input  logic  [3:0] cols,       // Входи стовпців (потрібна підтяжка Pull-Up)
    output logic  [3:0] rows,       // Виходи рядків
    output logic [15:0] keys_stable // 16 очищених кнопок (1 - натиснуто)
);
    // Подільник для сканування (~1 кГц)
    reg [15:0] clk_div;
    wire scan_en = (clk_div == 16'd50000);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_div <= '0;
        else if (scan_en) clk_div <= '0;
        else clk_div <= clk_div + 1'b1;
    end

    reg [1:0] row_sel;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_sel <= '0;
            rows    <= 4'b1110;
        end else if (scan_en) begin
            row_sel <= row_sel + 1'b1;
            case (row_sel)
                2'b00: rows <= 4'b1101;
                2'b01: rows <= 4'b1011;
                2'b10: rows <= 4'b0111;
                2'b11: rows <= 4'b1110;
            endcase
        end
    end

    reg [15:0] keys_raw;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            keys_raw <= '0;
        end else if (scan_en) begin
            case (row_sel)
                2'b00: keys_raw[3:0]   <= ~cols;
                2'b01: keys_raw[7:4]   <= ~cols;
                2'b10: keys_raw[11:8]  <= ~cols;
                2'b11: keys_raw[15:12] <= ~cols;
            endcase
        end
    end

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : deb_block
            debounce u_deb (
                .clk       (clk),
                .rst_n     (rst_n),
                .in_raw    (keys_raw[i]),
                .out_clean (keys_stable[i])
            );
        end
    endgenerate
endmodule
