module max7219_4x_matrix (
    input  logic        clk,    // Системная частота (например, 50 МГц)
    input  logic        rst_n,  // Сброс (активный 0)
    
    // Интерфейс к матричному индикатору
    output logic        sclk,   // Тактовая частота SPI (CLK)
    output logic        mosi,   // Данные (DIN)
    output logic        cs_n,   // Выбор чипа / Защелка (CS или LOAD)
    
    // Интерфейс данных: 4 знакоместа по 8 строк (каждая строка по 8 бит)
    // Всего: 4 модуля * 8 строк * 8 бит = 256 бит памяти дисплея
    input  logic [7:0]  display_ram [0:3][0:7] 
);

    // Внутренний делитель частоты для SPI (50МГц / 16 = 3.125 МГц)
    logic [3:0] clk_div;
    logic       spi_tick;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) clk_div <= 0;
        else        clk_div <= clk_div + 1;
    end
    assign spi_tick = (clk_div == 4'b1111); // Импульс каждые 16 тактов

    // Состояния конечного автомата
    typedef enum logic [2:0] {
        ST_INIT,        // Режим инициализации при включении
        ST_LOAD_ROW,    // Загрузка данных для очередной строки
        ST_TRANSMIT,    // Побитовый сдвиг 64 бит в SPI
        ST_CS_STROBE,   // Формирование импульса защелки LOAD/CS
        ST_DONE         // Ожидание следующего цикла обновления
    } state_t;
    
    state_t state;

    // Регистры управления
    logic [63:0] shift_reg;     // Сдвиговый регистр на 64 бита (4 матрицы * 16 бит)
    logic [5:0]  bit_cnt;       // Счетчик переданных бит (0..63)
    logic [3:0]  init_step;     // Шаг инициализации (всего 5 шагов)
    logic [2:0]  row_cnt;       // Индекс текущей строки (0..7)
    logic [15:0] delay_cnt;     // Таймер паузы между кадрами

    // Список команд инициализации (Повторяются 4 раза для 4 знакомест)
    always_comb begin
        case (init_step)
            4'd0: shift_reg = 64'h0900_0900_0900_0900; // Decode Mode: без декодирования
            4'd1: shift_reg = 64'h0A03_0A03_0A03_0A03; // Intensity: яркость (3 из 15)
            4'd2: shift_reg = 64'h0B07_0B07_0B07_0B07; // Scan Limit: все 8 строк активны
            4'd3: shift_reg = 4'h0C01_0C01_0C01_0C01; // Shutdown: включить матрицы (Normal)
            4'd4: shift_reg = 64'h0F00_0F00_0F00_0F00; // Display Test: выключен
            default: shift_reg = 64'h0000_0000_0000_0000;
        endcase
    end

    // Основной управляющий автомат
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= ST_INIT;
            init_step  <= 0;
            row_cnt    <= 0;
            bit_cnt    <= 0;
            sclk       <= 1'b0;
            mosi       <= 1'b0;
            cs_n       <= 1'b1;
            delay_cnt  <= 0;
        end else if (spi_tick) begin
            case (state)
                
                // 1. Инициализация всех 4-х чипов подряд
                ST_INIT: begin
                    cs_n    <= 1'b0;
                    bit_cnt <= 63;
                    state   <= ST_TRANSMIT;
                end

                // 2. Подготовка строки данных для 4 знакомест
                ST_LOAD_ROW: begin
                    cs_n    <= 1'b0;
                    bit_cnt <= 63;
                    // Формируем 64-битный пакет: [Адрес_Строки][Данные] для каждой из 4 матриц
                    // Адрес строки для MAX7219 — это (row_cnt + 1)
                    shift_reg <= {
                        {4'h0, row_cnt + 1'b1}, display_ram[3][row_cnt], // Матрица 4 (выход DOUT)
                        {4'h0, row_cnt + 1'b1}, display_ram[2][row_cnt], // Матрица 3
                        {4'h0, row_cnt + 1'b1}, display_ram[1][row_cnt], // Матрица 2
                        {4'h0, row_cnt + 1'b1}, display_ram[0][row_cnt]  // Матрица 1 (вход DIN от FPGA)
                    };
                    state   <= ST_TRANSMIT;
                end

                // 3. Последовательная передача 64 бит (SPI)
                ST_TRANSMIT: begin
                    if (sclk == 1'b0) begin
                        mosi <= shift_reg[bit_cnt]; // Выставляем бит данных
                        sclk <= 1'b1;               // Передний фронт (чип читает данные)
                    end else begin
                        sclk <= 1'b0;               // Задний фронт
                        if (bit_cnt == 0) begin
                            state <= ST_CS_STROBE;  // Все 64 бита ушли, фиксируем
                        end else begin
                            bit_cnt <= bit_cnt - 1;
                        end
                    end
                end

                // 4. Формирование импульса защелки (CS/LOAD)
                ST_CS_STROBE: begin
                    cs_n <= 1'b1; // Импульс вверх защелкивает данные во всех регистрах сразу
                    
                    if (init_step < 5) begin
                        init_step <= init_step + 1;
                        state     <= (init_step == 4) ? ST_LOAD_ROW : ST_INIT;
                    end else begin
                        if (row_cnt == 7) begin
                            row_cnt <= 0;
                            state   <= ST_DONE; // Обновили все 8 строк, уходим на паузу
                        end else begin
                            row_cnt <= row_cnt + 1;
                            state   <= ST_LOAD_ROW; // Переходим к следующей строке табло
                        end
                    end
                end

                // 5. Небольшая пауза между полными кадрами обновления матрицы
                ST_DONE: begin
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt == 16'hFFFF) begin // Регулирует частоту обновления экрана
                        state <= ST_LOAD_ROW;
                    end
                end

            endcase
        end
    end

endmodule
