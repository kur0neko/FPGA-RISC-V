`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/17/2025 02:29:33 AM
// Design Name: 
// Module Name: cpu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module cpu(
    input rst_n, clk,
    output reg [31:0] imem_addr,
    output reg [31:0] dmem_addr,
    input [31:0] imem_insn,
    inout reg [31:0] dmem_data,
    output reg dmem_wen
);

    // Register File
    reg [31:0] regfile [31:0];

    // Program Counter
    reg [31:0] program_counter = 0;

    // Pipeline Registers
    reg [31:0] IF_ID, ID_EX, EX_MEM, MEM_WB;
    reg [31:0] immgen, rs1_data, rs2_data, ALU, ALU_RESULT;

    // Control Signals
    reg stall;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // **Reset Logic**
            for (i = 0; i < 32; i = i + 1)
                regfile[i] = 0;

            program_counter = 0;
            IF_ID = 0;
            ID_EX = 0;
            EX_MEM = 0;
            MEM_WB = 0;
            ALU = 0;
            ALU_RESULT = 0;
            stall = 0;

            // Initialize memory control signals to prevent X values
            dmem_wen = 0;
            dmem_addr = 0;
        end 
        else begin
            // **Instruction Fetch (IF)**
            if (!stall) begin
                imem_addr = program_counter;
                program_counter = program_counter + 4;
                IF_ID = imem_insn;
            end

            // **Instruction Decode (ID)**
            ID_EX = IF_ID;
            rs1_data = regfile[IF_ID[19:15]];
            rs2_data = regfile[IF_ID[24:20]];

            // Immediate Generation for I-Type
            case (IF_ID[6:0])
                7'b0010011: begin // I-Type ALU Instructions
                    immgen = {{20{IF_ID[31]}}, IF_ID[31:20]};
                    if (IF_ID[14:12] == 3'b001 || IF_ID[14:12] == 3'b101)
                        immgen = {27'b0, IF_ID[24:20]};
                end
                default: 
                    immgen = 0;
            endcase  

            // **Execution (EX)**
            EX_MEM = ID_EX;
            case (ID_EX[6:0]) 
                7'b0010011: begin // I-Type ALU
                    case (ID_EX[14:12])
                        3'b000: ALU = rs1_data + immgen;  // ADDI
                        3'b111: ALU = rs1_data & immgen;  // ANDI
                        3'b110: ALU = rs1_data | immgen;  // ORI
                        3'b100: ALU = rs1_data ^ immgen;  // XORI
                        3'b010: ALU = ($signed(rs1_data) < $signed(immgen)) ? 1 : 0; // SLTI
                        3'b001: ALU = rs1_data << immgen[4:0]; // SLLI
                        3'b101: begin
                            if (ID_EX[30] == 1'b0)
                                ALU = rs1_data >> immgen[4:0]; // SRLI
                            else
                                ALU = $signed(rs1_data) >>> immgen[4:0]; // SRAI
                        end
                    endcase
                end
                7'b0110011: begin // R-Type ALU
                    case (ID_EX[14:12])
                        3'b000: begin // ADD/SUB
                            if (ID_EX[30] == 1'b0)
                                ALU = rs1_data + rs2_data; // ADD
                            else
                                ALU = rs1_data - rs2_data; // SUB
                        end
                        3'b111: ALU = rs1_data & rs2_data; // AND
                        3'b110: ALU = rs1_data | rs2_data; // OR
                        3'b100: ALU = rs1_data ^ rs2_data; // XOR
                        3'b010: ALU = ($signed(rs1_data) < $signed(rs2_data)) ? 1 : 0; // SLT
                        3'b001: ALU = rs1_data << rs2_data[4:0]; // SLL
                        3'b101: begin
                            if (ID_EX[30] == 1'b0)
                                ALU = rs1_data >> rs2_data[4:0]; // SRL
                            else
                                ALU = $signed(rs1_data) >>> rs2_data[4:0]; // SRA
                        end
                    endcase
                end
            endcase

            // **Memory (MEM)**
            ALU_RESULT = ALU; 
            MEM_WB = EX_MEM; 

            dmem_wen = 0;
            dmem_addr = 0;

            case (EX_MEM[6:0])
                7'b0100011: begin // Store (sw)
                    dmem_addr = ALU_RESULT;
                    dmem_wen = 1;
                    $display("📝 Storing Data: Mem[%h] <= %h", dmem_addr, regfile[EX_MEM[24:20]]);
                end
            endcase

            // **Writeback (WB)**
            if (MEM_WB[6:0] == 7'b0010011 || MEM_WB[6:0] == 7'b0110011) begin
                regfile[MEM_WB[11:7]] = ALU_RESULT;
                $display("✅ Writeback: x%0d <= %0h", MEM_WB[11:7], ALU_RESULT);
            end

            // **Debugging Information**
            $display("🔍 PC: %0h, Instruction: %0h, ALU Result: %0d", program_counter, imem_insn, ALU_RESULT);
        end
    end

    // **Memory Write Handling**
    assign dmem_data = (dmem_wen) ? regfile[EX_MEM[24:20]] : 32'bz;

endmodule
