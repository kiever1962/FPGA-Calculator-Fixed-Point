module top_calculator_max7219 (
    input  logic         clk,          // Системний клок 50 МГц
    input  logic         rst_n,        // Асинхронний скид (активний 0)
    
    // Фізичний інтерфейс матричної клавіатури 4х4
    input  logic [3:0]   keypad_cols,  // Входи стовпців (з Pull-Up на платі)
    output logic [3:0]   keypad_rows,  // Виходи рядків
    
    // Фізичні піни для 4-х окремих кнопок операцій (+, -, *, /)
    input  logic [3:0]   ops_buttons,  // Схема підключення: [ділення, множення, мінус, плюс]
    
    // Виходи на драйвер дисплея MAX7219 (SPI шина)
    output logic         max7219_clk,  
    output logic         max7219_data, 
    output logic         max7219_load  
);

    // Внутрішні сигнали клавіатури (Тепер повністю синхронізовані регістрово)
    logic        key_valid;
    logic [3:0]  key_code;
    logic        key_equal;
    logic [15:0] keys_stable;
    logic [3:0]  ops_stable;

    // Внутрішні шини зв'язку калькулятора
    logic signed [39:0] typed_value;
    logic               typed_valid;
    logic signed [39:0] reg_a;
    logic signed [39:0] reg_b;
    logic [1:0]         reg_op;        // 00:+, 01:-, 10:*, 11:/
    logic               calc_start;
    logic               calc_ready;
    logic signed [39:0] calc_result_bus;

    // Сигнали для блоку конвертації в BCD
    logic [23:0]        abs_int;
    logic [15:0]        frac_part;
    logic               is_negative;
    logic signed [39:0] abs_res;       

    // Керуючий автомат (FSM)
    typedef enum logic [1:0] {
        INPUT_OP_A,   
        INPUT_OP_B,   
        SHOW_RESULT   
    } state_t;
    state_t current_state;

    logic clear_input_acc;

    // Інстанс фізичної матричної клавіатури
    matrix_keypad_4x4 u_matrix_driver (
        .clk(clk), .rst_n(rst_n),
        .cols(keypad_cols), .rows(keypad_rows),
        .keys_stable(keys_stable)
    );

    // ВИПРАВЛЕНО: Кожен інстанс антибрязку працює СУТО ЗІ СВОЇМ БІТОМ входу та виходу!
    debounce u_db_plus  (.clk(clk), .rst_n(rst_n), .in_raw(~ops_buttons[0]), .out_clean(ops_stable[0]));
    debounce u_db_minus (.clk(clk), .rst_n(rst_n), .in_raw(~ops_buttons[1]), .out_clean(ops_stable[1]));
    debounce u_db_mult  (.clk(clk), .rst_n(rst_n), .in_raw(~ops_buttons[2]), .out_clean(ops_stable[2]));
    debounce u_db_div   (.clk(clk), .rst_n(rst_n), .in_raw(~ops_buttons[3]), .out_clean(ops_stable[3]));

    // Інстанс декодера в строби клавіш
    keypad_decoder u_key_decoder (
        .clk(clk), .rst_n(rst_n),
        .keys_stable(keys_stable), .ops_stable(ops_stable),
        .key_valid(key_valid), .key_code(key_code), .key_equal(key_equal)
    );

    // Логіка Керуючого Автомату (FSM)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_a           <= '0;
            reg_b           <= '0;
            reg_op          <= '0;
            calc_start      <= 1'b0;
            clear_input_acc <= 1'b0;
            current_state   <= INPUT_OP_A;
        end else begin
            calc_start      <= 1'b0;
            clear_input_acc <= 1'b0;

            if (key_valid && key_code == 4'hB) begin // Скинути 'C'
                reg_a           <= '0;
                reg_b           <= '0;
                reg_op          <= '0;
                clear_input_acc <= 1'b1;
                current_state   <= INPUT_OP_A;
            end else begin
                case (current_state)
                    INPUT_OP_A: begin
                        if (key_valid && key_code >= 4'hC && key_code <= 4'hF) begin
                            reg_a           <= typed_value;   
                            reg_op          <= key_code[1:0]; 
                            clear_input_acc <= 1'b1;          
                            current_state   <= INPUT_OP_B;
                        end
                    end
                    INPUT_OP_B: begin
                        if (key_equal) begin
                            reg_b           <= typed_value;   
                            calc_start      <= 1'b1;          
                            clear_input_acc <= 1'b1;          
                            current_state   <= SHOW_RESULT;
                        end
                    end
                    SHOW_RESULT: begin
                        if (key_valid && (key_code <= 4'd9 || key_code == 4'hA)) begin
                            reg_a           <= '0;
                            reg_b           <= '0;
                            clear_input_acc <= 1'b1; 
                            current_state   <= INPUT_OP_A;
                        end
                    end
                    default: current_state <= INPUT_OP_A;
                endcase
            end
        end
    end
    // (Продовження модуля top_calculator_max7219)

    // Мультиплексор екрана: обирає, що зараз виводити на MAX7219
    logic signed [39:0] active_value;
    always_comb begin
        if (current_state == SHOW_RESULT) active_value = calc_result_bus;
        else                              active_value = typed_value;
    end

    // ВИПРАВЛЕНО: Строго аналізуємо 39-й біт знаку (signed)
    always_comb begin
        is_negative = active_value[39]; 
        if (is_negative) begin
            abs_res = -active_value; 
        end else begin
            abs_res = active_value;
        end
        abs_int   = abs_res[39:16]; // Старші 24 біти - ціла частина
        frac_part = abs_res[15:0];  // Молодші 16 бітів - дріб
    end

    // Крок 1: Оновлений Double Dabble для дробової частини З МАТЕМАТИЧНИМ ОКРУГЛЕННЯМ (+32'h8000)
    logic [11:0] bcd_frac;
    always_comb begin
        logic [11:0] bcd;
        logic [9:0]  val; 
        bcd = '0;
        val = 10'(((32'(frac_part) * 32'd1000) + 32'h8000) >> 16); 
        
        for (int i = 0; i < 10; i++) begin
            if (bcd[3:0]  >= 5) bcd[3:0]  = bcd[3:0]  + 4'd3;
            if (bcd[7:4]  >= 5) bcd[7:4]  = bcd[7:4]  + 4'd3;
            if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 4'd3;
            bcd = {bcd[10:0], val[9]}; val = {val[8:0], 1'b0};
        end
        bcd_frac = bcd;
    end

    // Крок 2: Double Dabble для цілої частини (24 біти -> 5 BCD розрядів)
    logic [19:0] bcd_int;
    always_comb begin
        logic [19:0] bcd;
        logic [23:0] val;
        bcd = '0; 
        val = abs_int;
        for (int i = 0; i < 24; i++) begin
            for (int j = 0; j < 5; j++) begin
                if (bcd[j*4 +: 4] >= 5) bcd[j*4 +: 4] = bcd[j*4 +: 4] + 4'd3;
            end
            bcd = {bcd[18:0], val[23]}; val = {val[22:0], 1'b0};
        end
        bcd_int = bcd;
    end

    // Крок 3: Пакування паралельної шини під MAX7219 з динамічним гасінням нулів
    logic [31:0] bcd_parallel_bus;
    localparam BLANK = 4'hF; 
    localparam MINUS = 4'hA; 

    always_comb begin
        logic [3:0] d7, d6, d5, d4, d3;
        d7 = bcd_int[19:16];
        d6 = bcd_int[15:12];
        d5 = bcd_int[11:8];
        d4 = bcd_int[7:4];
        d3 = bcd_int[3:0]; // Останній розряд перед комою (ніколи не гаситься)

        if (d7 == 4'd0) begin
            if (is_negative && (d6 != 4'd0)) begin
                d7 = MINUS;
            end else begin
                d7 = BLANK;
                if (d6 == 4'd0) begin
                    if (is_negative && (d5 != 4'd0)) begin
                        d6 = MINUS;
                    end else begin
                        d6 = BLANK;
                        if (d5 == 4'd0) begin
                            if (is_negative && (d4 != 4'd0)) begin
                                d5 = MINUS;
                            end else begin
                                d5 = BLANK;
                                if (d4 == 4'd0) begin
                                    if (is_negative) d4 = MINUS;
                                    else             d4 = BLANK;
                                end else if (is_negative) begin
                                    d5 = MINUS;
                                end
                            end
                        end else if (is_negative) begin
                            d6 = MINUS;
                        end
                    end
                end else if (is_negative) begin
                    d7 = MINUS;
                end
            end
        end

        // Формування фінальної 32-бітної шини для індикатора (8 цифр по 4 біти)
        bcd_parallel_bus[31:28] = d7; 
        bcd_parallel_bus[27:24] = d6;
        bcd_parallel_bus[23:20] = d5;
        bcd_parallel_bus[19:16] = d4;
        bcd_parallel_bus[15:12] = d3;      
        bcd_parallel_bus[11:8]  = bcd_frac[11:8]; // 1-й знак після коми
        bcd_parallel_bus[7:4]   = bcd_frac[7:4];  // 2-й знак після коми
        bcd_parallel_bus[3:0]   = bcd_frac[3:0];  // 3-й знак після коми
    end

    // Модуль накопичення та декодування введення чисел з клавіатури
    q24_16_input_dec u_input (
        .clk(clk), .rst_n(rst_n & ~clear_input_acc), 
        .key_valid(key_valid), .key_code(key_code),
        .q_value(typed_value), .q_valid(typed_valid)
    );

    // Обчислювальний блок
    q24_16_calculator u_calculator (
        .clk(clk), .rst_n(rst_n),
        .a(reg_a), .b(reg_b), .op(reg_op), 
        .start(calc_start), .ready(calc_ready),
        .result_out(calc_result_bus)
    );

    // SPI Контролер дисплея MAX7219
    M7219_FixedPoint u_spi_display (
        .clk(clk), .parallel(bcd_parallel_bus), .dot_pos(3'd3), 
        .clk_out(max7219_clk), .data_out(max7219_data), .load(max7219_load)
    );

endmodule
