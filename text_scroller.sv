module text_scroller #(
    parameter TEXT_LEN = 10,       // Длина бегущей строки в символах
    parameter CLK_FREQ = 50000000  // Частота генератора (50 МГц)
)(
    input  logic        clk,
    input  logic        rst_n,
    
    // Выходной интерфейс к драйверу MAX7219
    output logic [7:0]  display_ram [0:3][0:7]
);

    // 1. Память для текста (Храним ASCII-коды символов)
    logic [7:0] text_rom [0:TEXT_LEN-1];
    initial begin
        // Инициализируем строку (например: "FPGA ROCKS ")
        text_rom[0] = "F"; text_rom[1] = "P"; text_rom[2] = "G"; text_rom[3] = "A";
        text_rom[4] = " "; text_rom[5] = "R"; text_rom[6] = "O"; text_rom[7] = "C";
        text_rom[8] = "K"; text_rom[9] = "S";
    end

    // 2. Генератор скорости бегущей строки (Сдвиг каждые ~100 мс)
    localparam SCROLL_SPEED = CLK_FREQ / 10; // 100 мс при 50 МГц
    logic [23:0] speed_counter;
    logic        scroll_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            speed_counter <= 0;
            scroll_tick   <= 1'b0;
        end else begin
            if (speed_counter >= SCROLL_SPEED - 1) begin
                speed_counter <= 0;
                scroll_tick   <= 1'b1;
            end else begin
                speed_counter <= speed_counter + 1'b1;
                scroll_tick   <= 1'b0;
            end
        end
    end

    // Счетчик текущего глобального сдвига в пикселях
    localparam MAX_SCROLL_PIXELS = TEXT_LEN * 8;
    logic [9:0] scroll_pos; // Позиция левого края экрана в пикселях текста

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scroll_pos <= 0;
        end else if (scroll_tick) begin
            if (scroll_pos >= MAX_SCROLL_PIXELS - 1)
                scroll_pos <= 0; // Повтор строки по кругу
            else
                scroll_pos <= scroll_pos + 1'b1;
        end
    end

    // 3. ПЗУ шрифта 8х8 (только используемые буквы ради краткости)
    function automatic logic [7:0] get_font_line(input logic [7:0] ascii, input logic [2:0] row);
        case (ascii)
            "F": case(row) 3'd0: return 8'hFF; 3'd1: return 8'h80; 3'd2: return 8'hF0; 3'd3: return 8'h80; default: return 8'h80; endcase
            "P": case(row) 3'd0: return 8'hF8; 3'd1: return 8'h88; 3'd2: return 8'hF8; 3'd3: return 8'h80; default: return 8'h80; endcase
            "G": case(row) 3'd0: return 8'h78; 3'd1: return 8'h80; 3'd2: return 8'h8C; 3'd3: return 8'h88; default: return 8'h70; endcase
            "A": case(row) 3'd0: return 8'h20; 3'd1: return 8'h50; 3'd2: return 8'h88; 3'd3: return 8'hFF; default: return 8'h88; endcase
            "R": case(row) 3'd0: return 8'hF8; 3'd1: return 8'h88; 3'd2: return 8'hF8; 3'd3: return 8'h90; default: return 8'h88; endcase
            "O": case(row) 3'd0: return 8'h70; 3'd1: return 8'h88; 3'd2: return 8'h88; 3'd3: return 8'h88; default: return 8'h70; endcase
            "C": case(row) 3'd0: return 8'h78; 3'd1: return 8'h80; 3'd2: return 8'h80; 3'd3: return 8'h80; default: return 8'h78; endcase
            "K": case(row) 3'd0: return 8'h88; 3'd1: return 8'h90; 3'd2: return 8'hE0; 3'd3: return 8'h90; default: return 8'h88; endcase
            "S": case(row) 3'd0: return 8'h78; 3'd1: return 8'h80; 3'd2: return 8'h70; 3'd3: return 8'h08; default: return 8'hF0; endcase
            default: return 8'h00; // Пробел и неизвестные символы
        endcase
    endfunction

    // 4. Логика формирования кадра (Окно просмотра)
    always_comb begin
        for (int r = 0; r < 8; r++) begin : gen_rows
            // Все объявления строго в начале блока (исправление ошибки Quartus)
            logic [3:0]  char_index0;
            logic [3:0]  char_index1;
            logic [3:0]  char_index2;
            logic [3:0]  char_index3;
            logic [3:0]  char_index4;
            logic [7:0]  line0;
            logic [7:0]  line1;
            logic [7:0]  line2;
            logic [7:0]  line3;
            logic [7:0]  line4;
            logic [39:0] wide_row;
            logic [31:0] shifted_row;
            logic [2:0]  sub_pixel_shift;
            
            // Вычисляем, какие символы текста попадают в текущее окно просмотра
            char_index0 = (scroll_pos / 8) % TEXT_LEN;
            char_index1 = (char_index0 + 1) % TEXT_LEN;
            char_index2 = (char_index0 + 2) % TEXT_LEN;
            char_index3 = (char_index0 + 3) % TEXT_LEN;
            char_index4 = (char_index0 + 4) % TEXT_LEN;
            
            // Извлекаем нужную строку пикселей для каждого из 5 символов
            line0 = get_font_line(text_rom[char_index0], r[2:0]);
            line1 = get_font_line(text_rom[char_index1], r[2:0]);
            line2 = get_font_line(text_rom[char_index2], r[2:0]);
            line3 = get_font_line(text_rom[char_index3], r[2:0]);
            line4 = get_font_line(text_rom[char_index4], r[2:0]);
            
            // Склеиваем их в одну широкую строку (40 бит)
            wide_row = {line0, line1, line2, line3, line4};
            
            // Сдвигаем строку влево на величину внутрисимвольного остатка
            sub_pixel_shift = scroll_pos % 8;
            shifted_row     = wide_row << sub_pixel_shift;
            
            // Распределяем полученные 32 бита по 4 матрицам в display_ram
            display_ram[0][r] = shifted_row[31:24]; // Левое знакоместо (Матрица 1)
            display_ram[1][r] = shifted_row[23:16]; // Матрица 2
            display_ram[2][r] = shifted_row[15:8];  // Матрица 3
            display_ram[3][r] = shifted_row[7:0];   // Правое знакоместо (Матрица 4)
        end
    end

endmodule
