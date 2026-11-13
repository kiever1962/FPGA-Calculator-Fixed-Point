module keypad_decoder (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [15:0] keys_stable,  // Матриця 4х4 (цифри, ., C, =)
    input  logic [3:0]  ops_stable,   // 4 окремі кнопки (+, -, *, /)
    output logic        key_valid,
    output logic [3:0]  key_code,
    output logic        key_equal
);
    logic [15:0] keys_prev;
    logic [3:0]  ops_prev;
    logic [15:0] keys_pressed;
    logic [3:0]  ops_pressed;
    
    assign keys_pressed = keys_stable & ~keys_prev;
    assign ops_pressed  = ops_stable & ~ops_prev;

    // Синхронна фіксація фронтів натискання
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            keys_prev <= '0;
            ops_prev  <= '0;
        end else begin
            keys_prev <= keys_stable;
            ops_prev  <= ops_stable;
        end
    end

    // ПОВНІСТЮ СИНХРОННЕ (РЕГІСТРОВЕ) ДЕКОДУВАННЯ
    // ВИПРАВЛЕНО: 'negedge rst_n' прописано синтаксично коректно
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_valid <= 1'b0;
            key_equal <= 1'b0;
            key_code  <= 4'h0;
        end else begin
            // Дефолтні значення для синхронного регістра
            key_valid <= 1'b0;
            key_equal <= 1'b0;

            // Перевірка окремих кнопок математичних операцій
            if      (ops_pressed[0]) begin key_valid <= 1'b1; key_code <= 4'hC; end // '+'
            else if (ops_pressed[1]) begin key_valid <= 1'b1; key_code <= 4'hD; end // '-'
            else if (ops_pressed[2]) begin key_valid <= 1'b1; key_code <= 4'hE; end // '*'
            else if (ops_pressed[3]) begin key_valid <= 1'b1; key_code <= 4'hF; end // '/'
            
            // Перевірка кнопок матриці
            else if (keys_pressed[0])  begin key_valid <= 1'b1; key_code <= 4'd1; end // '1'
            else if (keys_pressed[1])  begin key_valid <= 1'b1; key_code <= 4'd2; end // '2'
            else if (keys_pressed[2])  begin key_valid <= 1'b1; key_code <= 4'd3; end // '3'
            else if (keys_pressed[3])  begin key_equal <= 1'b1;                    end // '='
            
            else if (keys_pressed[4])  begin key_valid <= 1'b1; key_code <= 4'd4; end // '4'
            else if (keys_pressed[5])  begin key_valid <= 1'b1; key_code <= 4'd5; end // '5'
            else if (keys_pressed[6])  begin key_valid <= 1'b1; key_code <= 4'd6; end // '6'
            
            else if (keys_pressed[8])  begin key_valid <= 1'b1; key_code <= 4'd7; end // '7'
            else if (keys_pressed[9])  begin key_valid <= 1'b1; key_code <= 4'd8; end // '8'
            else if (keys_pressed[10]) begin key_valid <= 1'b1; key_code <= 4'd9; end // '9'
            
            else if (keys_pressed[12]) begin key_valid <= 1'b1; key_code <= 4'hA; end // '.'
            else if (keys_pressed[13]) begin key_valid <= 1'b1; key_code <= 4'd0; end // '0'
            else if (keys_pressed[14]) begin key_valid <= 1'b1; key_code <= 4'hB; end // 'C'
        end
    end
endmodule
