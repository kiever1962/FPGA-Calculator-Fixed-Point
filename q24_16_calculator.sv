module q24_16_calculator (
    input  logic         clk,
    input  logic         rst_n,
    input  logic signed [39:0] a,      // Операнд А (Q24.16)
    input  logic signed [39:0] b,      // Операнд B (Q24.16)
    input  logic [1:0]   op,           // 00:+, 01:-, 10:*, 11:/
    input  logic         start,        // Імпульс запуску
    output logic         ready,        // Прапорець готовності
    output logic signed [39:0] result_out
);
    logic [39:0] div_quotient;
    logic        div_start;
    logic        div_ready;
    logic [79:0] div_reg;
    logic [39:0] div_den;
    logic        div_sign;
    logic [5:0]  div_count;

    typedef enum logic [1:0] {DIV_IDLE, DIV_CALC, DIV_DONE} div_state_t;
    div_state_t div_state;

    logic [39:0] abs_a, abs_b;
    assign abs_a = (a[39] == 1'b1) ? -a : a;
    assign abs_b = (b[39] == 1'b1) ? -b : b;

    assign div_start = (start && op == 2'b11 && div_state == DIV_IDLE);

    logic [79:0] div_reg_shifted;
    logic [40:0] sub_res;
    
    assign div_reg_shifted = {div_reg[78:0], 1'b0};
    assign sub_res = {1'b0, div_reg_shifted[79:40]} - {1'b0, div_den};

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_state    <= DIV_IDLE;
            div_reg      <= '0;
            div_den      <= '0;
            div_count    <= '0;
            div_sign     <= 1'b0;
            div_ready    <= 1'b0;
            div_quotient <= '0;
        end else begin
            case (div_state)
                DIV_IDLE: begin
                    div_ready <= 1'b0;
                    if (div_start) begin
                        if (b == '0) begin
                            div_quotient <= 40'h7FFFFFFFFF; // Максимальне число при діленні на 0
                            div_ready    <= 1'b1;
                        end else begin
                            div_reg   <= {24'b0, abs_a, 16'b0}; 
                            div_den   <= abs_b;
                            div_sign  <= a[39] ^ b[39];
                            div_count <= 6'd40;
                            div_state <= DIV_CALC;
                        end
                    end
                end
                DIV_CALC: begin
                    if (sub_res[40] == 1'b0) begin
                        div_reg <= {sub_res[39:0], div_reg_shifted[39:1], 1'b1};
                    end else begin
                        div_reg <= div_reg_shifted;
                    end
                    div_count <= div_count - 1'b1;
                    if (div_count == 6'd1) div_state <= DIV_DONE;
                end
                DIV_DONE: begin
                    div_quotient <= div_sign ? -div_reg[39:0] : div_reg[39:0];
                    div_ready    <= 1'b1;
                    div_state    <= DIV_IDLE;
                end
                default: div_state <= DIV_IDLE;
            endcase
        end
    end

    logic signed [79:0] full_mul;
    assign full_mul = a * b; 

    logic signed [39:0] calc_res;
    logic               calc_ready;
    logic               div_busy;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            calc_res   <= '0;
            calc_ready <= 1'b0;
            div_busy   <= 1'b0;
        end else begin
            calc_ready <= 1'b0;

            if (start) begin
                case (op)
                    2'b00: begin // +
                        calc_res   <= a + b;
                        calc_ready <= 1'b1;
                    end
                    2'b01: begin // -
                        calc_res   <= a - b;
                        calc_ready <= 1'b1;
                    end
                    2'b10: begin // *
                        calc_res   <= full_mul[55:16]; // Відсікання до формату Q24.16
                        calc_ready <= 1'b1;
                    end
                    2'b11: begin // /
                        if (b == '0) begin
                            calc_res   <= 40'h7FFFFFFFFF; 
                            calc_ready <= 1'b1;
                            div_busy   <= 1'b0;
                        end else begin
                            div_busy   <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end else if (div_busy && div_ready) begin
                calc_res   <= div_quotient;
                calc_ready <= 1'b1;
                div_busy   <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result_out <= '0; 
            ready      <= 1'b0;
        end else begin
            ready <= calc_ready;
            if (calc_ready) result_out <= calc_res;
        end
    end
endmodule
