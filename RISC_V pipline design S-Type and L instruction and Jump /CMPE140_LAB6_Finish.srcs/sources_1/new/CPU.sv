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

// ============================
// CPU Module
// Supports R-type, I-type, Load/Store
// Includes byte-enable logic for partial memory writes
// ============================

module cpu(
    input rst_n, clk,
    output reg [31:0] imem_addr,      // Address for instruction memory
    output reg [31:0] dmem_addr,      // Address for data memory
    input [31:0] imem_insn,           // Instruction fetched from instruction memory
    inout reg [31:0] dmem_data,       // Data bus to/from data memory
    output reg dmem_wen,              // Write enable for data memory
    output reg [3:0] byte_en          // Byte-enable signal for partial store operations
);

    // Register File (32 general-purpose registers)
    reg [31:0] regfile [31:0];

    // Program Counter
    reg [31:0] program_counter = 0;

    // Pipeline Registers
    reg [31:0] IF_ID, ID_EX, EX_MEM, MEM_WB;
    reg [31:0] immgen, rs1_data, rs2_data, ALU, ALU_RESULT;
    reg [31:0] LOAD_DATA; // Holds result of load operations

    // Control Signals
    reg stall;
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset logic
            for (i = 0; i < 32; i = i + 1)
                regfile[i] = 0;

            program_counter = 0;
            IF_ID = 0; ID_EX = 0; EX_MEM = 0; MEM_WB = 0;
            ALU = 0; ALU_RESULT = 0; LOAD_DATA = 0;
            stall = 0; dmem_wen = 0; dmem_addr = 0;
            byte_en = 4'b0000;
        end else begin

            // -----------------------------
            // Instruction Fetch (IF)
            // -----------------------------
            if (!stall) begin
                imem_addr = program_counter;
                program_counter = program_counter + 4;
                IF_ID = imem_insn;
            end

            // -----------------------------
            // Instruction Decode (ID)
            // -----------------------------
            ID_EX = IF_ID;
            rs1_data = regfile[IF_ID[19:15]];
            rs2_data = regfile[IF_ID[24:20]];

            // Immediate generator
            case (IF_ID[6:0])
                7'b0010011, 7'b0000011: begin // I-type (ALU or Load)
                    immgen = {{20{IF_ID[31]}}, IF_ID[31:20]};
                    if (IF_ID[14:12] == 3'b001 || IF_ID[14:12] == 3'b101)
                        immgen = {27'b0, IF_ID[24:20]}; // shift amount
                end
                7'b0100011: begin // Store
                    immgen = {{20{IF_ID[31]}}, IF_ID[31:25], IF_ID[11:7]};
                end
                default: immgen = 0;
            endcase

            // -----------------------------
            // Execute (EX)
            // -----------------------------
            EX_MEM = ID_EX;
            case (ID_EX[6:0])
                // I-type ALU
                7'b0010011: begin
                    case (ID_EX[14:12])
                        3'b000: ALU = rs1_data + immgen; // ADDI
                        3'b111: ALU = rs1_data & immgen; // ANDI
                        3'b110: ALU = rs1_data | immgen; // ORI
                        3'b100: ALU = rs1_data ^ immgen; // XORI
                        3'b010: ALU = ($signed(rs1_data) < $signed(immgen)) ? 1 : 0; // SLTI
                        3'b001: ALU = rs1_data << immgen[4:0]; // SLLI
                        3'b101: ALU = (ID_EX[30]) ? $signed(rs1_data) >>> immgen[4:0] : rs1_data >> immgen[4:0]; // SRLI/SRAI
                    endcase
                end
                // R-type ALU
                7'b0110011: begin
                    case (ID_EX[14:12])
                        3'b000: ALU = (ID_EX[30]) ? rs1_data - rs2_data : rs1_data + rs2_data; // SUB/ADD
                        3'b111: ALU = rs1_data & rs2_data;
                        3'b110: ALU = rs1_data | rs2_data;
                        3'b100: ALU = rs1_data ^ rs2_data;
                        3'b010: ALU = ($signed(rs1_data) < $signed(rs2_data)) ? 1 : 0;
                        3'b001: ALU = rs1_data << rs2_data[4:0];
                        3'b101: ALU = (ID_EX[30]) ? $signed(rs1_data) >>> rs2_data[4:0] : rs1_data >> rs2_data[4:0];
                    endcase
                end
                // Address calculation for Load/Store
                7'b0100011, 7'b0000011: begin
                    ALU = rs1_data + immgen;
                end
            endcase

            // -----------------------------
            // Memory (MEM)
            // -----------------------------
            ALU_RESULT = ALU;
            MEM_WB = EX_MEM;
            dmem_wen = 0;
            dmem_addr = 0;
            byte_en = 4'b0000;

            case (EX_MEM[6:0])
                // Store operations
                7'b0100011: begin
                    dmem_addr = ALU_RESULT;
                    dmem_wen = 1;
                    case (EX_MEM[14:12])
                        3'b000: case (ALU_RESULT[1:0]) // SB
                            2'b00: byte_en = 4'b0001;
                            2'b01: byte_en = 4'b0010;
                            2'b10: byte_en = 4'b0100;
                            2'b11: byte_en = 4'b1000;
                        endcase
                        3'b001: case (ALU_RESULT[1:0]) // SH
                            2'b00: byte_en = 4'b0011;
                            2'b10: byte_en = 4'b1100;
                            default: byte_en = 4'b0000; // Unaligned
                        endcase
                        3'b010: byte_en = 4'b1111; // SW
                        default: byte_en = 4'b0000;
                    endcase
                    $display("📝 Store @ %h, data = %h, byte_en = %b", dmem_addr, regfile[EX_MEM[24:20]], byte_en);
                end
                // Load operations
                7'b0000011: begin
                    dmem_addr = ALU_RESULT;
                    byte_en = 4'b0000; // Loads don't enable memory write
                    case (EX_MEM[14:12])
                        // Load Byte (signed)
                        3'b000: case (ALU_RESULT[1:0])
                            2'b00: LOAD_DATA = {{24{dmem_data[7]}}, dmem_data[7:0]};
                            2'b01: LOAD_DATA = {{24{dmem_data[15]}}, dmem_data[15:8]};
                            2'b10: LOAD_DATA = {{24{dmem_data[23]}}, dmem_data[23:16]};
                            2'b11: LOAD_DATA = {{24{dmem_data[31]}}, dmem_data[31:24]};
                        endcase
                        // Load Halfword (signed)
                        3'b001: case (ALU_RESULT[1:0])
                            2'b00: LOAD_DATA = {{16{dmem_data[15]}}, dmem_data[15:0]};
                            2'b10: LOAD_DATA = {{16{dmem_data[31]}}, dmem_data[31:16]};
                            default: LOAD_DATA = 32'hDEADBEEF;
                        endcase
                        // Load Word
                        3'b010: LOAD_DATA = dmem_data;
                        // Load Byte Unsigned
                        3'b100: case (ALU_RESULT[1:0])
                            2'b00: LOAD_DATA = {24'b0, dmem_data[7:0]};
                            2'b01: LOAD_DATA = {24'b0, dmem_data[15:8]};
                            2'b10: LOAD_DATA = {24'b0, dmem_data[23:16]};
                            2'b11: LOAD_DATA = {24'b0, dmem_data[31:24]};
                        endcase
                        // Load Halfword Unsigned
                        3'b101: case (ALU_RESULT[1:0])
                            2'b00: LOAD_DATA = {16'b0, dmem_data[15:0]};
                            2'b10: LOAD_DATA = {16'b0, dmem_data[31:16]};
                            default: LOAD_DATA = 32'hDEADBEEF;
                        endcase
                    endcase
                    $display("📥 Load @ %h, result = %h", dmem_addr, LOAD_DATA);
                end
            endcase

            // -----------------------------
            // Write Back (WB)
            // -----------------------------
            if (MEM_WB[6:0] == 7'b0010011 || MEM_WB[6:0] == 7'b0110011) begin
                regfile[MEM_WB[11:7]] = ALU_RESULT;
                $display("✅ Writeback: x%0d <= %0h", MEM_WB[11:7], ALU_RESULT);
            end
            if (MEM_WB[6:0] == 7'b0000011) begin
                regfile[MEM_WB[11:7]] = LOAD_DATA;
                $display("✅ Load WB: x%0d <= %0h", MEM_WB[11:7], LOAD_DATA);
            end

            // -----------------------------
            // Debug Info
            // -----------------------------
            $display("🔍 PC: %0h, Instruction: %0h, ALU Result: %0d", program_counter, imem_insn, ALU_RESULT);
        end
    end
     //trace files
    integer file1, file2, clear1, clear2, CC;
    //pc
    always_comb begin
        file1 = $fopen("C:/Users/NOTAMAC/CMPE140_LAB6_Finish/CMPE140_LAB6_Finish.srcs/sim_1/imports/Downloads/pc.txt", "a");
        if (program_counter <= 0) begin
            clear1 = $fopen("C:/Users/NOTAMAC/CMPE140_LAB6_Finish/CMPE140_LAB6_Finish.srcs/sim_1/imports/Downloads/pc.txt", "w");
            $fwrite(clear1, "");            
        end
        if (file1) begin
            $display("Opening file!");
            $fwrite(file1, "PC: %0h\n", program_counter);
            $fclose(file1);
        end else begin
            $display("Error opening file!");
        end
    end
    //cc, register number, and value
    always_comb begin
        file2 = $fopen("C:/Users/NOTAMAC/CMPE140_LAB6_Finish/CMPE140_LAB6_Finish.srcs/sim_1/imports/Downloads/result.txt", "a");
        CC = program_counter / 4;        
        if (program_counter <= 0) begin
            clear2 = $fopen("C:/Users/NOTAMAC/CMPE140_LAB6_Finish/CMPE140_LAB6_Finish.srcs/sim_1/imports/Downloads/result.txt", "w");
            $fwrite(clear2, "");            
        end
        if (file2) begin
            $display("Opening file!");
            $fwrite(file2, "CC: %0d, Register: x%0d, Value: %0d\n", CC, MEM_WB[11:7], $signed(ALU_RESULT));
            $fclose(file2);
        end else begin
            $display("Error opening file!");
        end
    end
    // **Memory Write Handling**
    assign dmem_data = (dmem_wen) ? regfile[EX_MEM[24:20]] : 32'bz;

endmodule




