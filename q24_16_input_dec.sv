module q24_16_input_dec (
    input  logic         clk,
    input  logic         rst_n,          // Асинхронний скид
    input  logic         key_valid,      // Строб натискання клавіші (1 такт)
    input  logic [3:0]   key_code,       // Код натиснутої клавіші
    
    output logic signed [39:0] q_value,  // Сформоване число у форматі Q24.16
    output logic         q_valid         // Прапорець стабільності виходу
);

    logic [23:0] int_part;         // Ціла частина числа (до 5 знаків)
    logic [11:0] frac_accumulator; // Накопичувач дробу як цілого числа (макс 999)
    logic        is_frac;          // Режим введення: 0 - ціла частина, 1 - дріб
    logic [1:0]  frac_digits;      // Лічильник кількості введених цифр після коми (0, 1, 2, 3)

    // Використовуємо строго logic [31:0] для констант масштабування Q16.
    // Це повністю виключає помилки інтерпретації типів компилятором Quartus.
    localparam logic [31:0] INV_SCALE [1:3] = '{32'd6554, 32'd655, 32'd66};

    // Комбінаційний розрахунок фінальної дробової частини у форматі Q16
    logic [31:0] frac_q16_calc;
    always_comb begin
        if (frac_digits == 2'd0) begin
            frac_q16_calc = '0;
        end else begin
            frac_q16_calc = 32'(frac_accumulator) * INV_SCALE[frac_digits];
        end
    end

    // Послідовна логіка введення
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            int_part         <= '0;
            frac_accumulator <= '0;
            is_frac          <= 1'b0;
            frac_digits      <= '0;
            q_valid          <= 1'b0;
        end else begin
            q_valid <= 1'b0;

            if (key_valid) begin
                if (key_code == 4'hA) begin
                    // Натиснуто КРАПКУ: перемикаємо режим на дробовий
                    is_frac <= 1'b1;
                    q_valid <= 1'b1;
                end 
                else if (key_code <= 4'd9) begin
                    // Натиснуто ЦИФРУ
                    if (!is_frac) begin
                        // Введення цілої частини
                        if (int_part < 24'd99999) begin
                            int_part <= (int_part * 4'd10) + key_code;
                            q_valid  <= 1'b1;
                        end
                    end 
                    else begin
                        // Введення дробової частини (строго до 3 знаків)
                        if (frac_digits < 2'd3) begin
                            frac_accumulator <= (frac_accumulator * 4'd10) + key_code;
                            frac_digits      <= frac_digits + 1'b1;
                            q_valid          <= 1'b1;
                        end
                    end
                end
            end
        end
    end

    // БЕЗПЕЧНА ЗБІРКА: примусово розширюємо цілу частину нулями зліва 
    // і додаємо нижні 16 бітів розрахованого дробу.
    assign q_value = {16'b0, int_part, frac_q16_calc[15:0]};

endmodule
