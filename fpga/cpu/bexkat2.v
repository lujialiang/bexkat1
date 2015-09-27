`timescale 1ns / 1ns

module bexkat2(
  input clk,
  input reset_n,
  input waitrequest,
  output [31:0] address,
  output reg read,
  output reg write,
  output halt,
  input [2:0] interrupt,
  output int_en,
  output [3:0] exception,
  input [31:0] readdata,
  output [31:0] writedata,
  output [3:0] byteenable);

// Control signals
wire reg_write;
wire [2:0] alu_func, int_func;
wire addrsel, ir_write, vectoff_write;
wire [4:0] reg_read_addr1, reg_read_addr2, reg_write_addr;
wire [1:0] marsel, int1sel, int2sel, ccrsel;
wire [2:0] pcsel, alu1sel, alu2sel;
wire [3:0] regsel, mdrsel;
wire fp_aeb, fp_agb, fp_alb;

// Data paths
wire [31:0] alu_out, reg_data_out1, reg_data_out2;
wire [31:0] ir_next, vectoff_next, fp_cvtis_out;
wire [31:0] fp_cvtsi_out;
wire [63:0] int_out;
wire [4:0] ccr_next;
wire alu_carry, alu_negative, alu_overflow, alu_zero;

// Special registers
reg [31:0] mdr, mdr_next, mar, pc, aluval, ir, busin_be, vectoff;
reg [32:0] pc_next, mar_next;
reg [31:0] reg_data_in, alu_in1, alu_in2, int_in1, int_in2;
reg [63:0] intval;
reg [4:0] ccr;
reg [3:0] status, status_next;

// opcode format
wire [31:0] ir_sval = { {16{ir[23]}}, ir[23:20], ir[11:0] };
wire [31:0] ir_uval = { 16'h0000, ir[23:20], ir[11:0] };

// Convenience mappings
wire super_mode = status[3];

// Data switching logic
assign address = (addrsel ? mar : pc);
assign ir_next = (ir_write ? readdata : ir);
assign vectoff_next = (vectoff_write ? mdr : vectoff);

always @(posedge clk or negedge reset_n)
begin
  if (!reset_n) begin
    pc <= 'h0;
    ir <= 0;
    mdr <= 0;
    mar <= 0;
    aluval <= 0;
    intval <= 0;
    ccr <= 5'h0;
    vectoff <= 'hffffffc0;
    status <= 4'b1000; // start in supervisor mode
  end else begin
    pc <= pc_next[31:0];
    ir <= ir_next;
    mdr <= mdr_next;
    mar <= mar_next[31:0];
    aluval <= alu_out;
    intval <= int_out;
    ccr <= ccr_next;
    vectoff <= vectoff_next;
    status <= status_next;
  end
end

// All of the datapath options
always @* begin
  status_next = status;
  case (pcsel)
    3'h0: pc_next = pc;
    3'h1: pc_next = pc + 'h4;
    3'h2: pc_next = { 1'b0, mar };
    3'h3: pc_next = { 1'b0, pc } + ir_sval;  // relative branching
    3'h4: pc_next = { 1'b0, aluval }; // reg offset
    3'h5: pc_next = { 1'b0, vectoff } + { exception, 2'b00 }; // exception vectors 
    default: pc_next = pc;
  endcase  
  case (marsel)
    2'h0: mar_next = mar;
    2'h1: mar_next = readdata;
    2'h2: mar_next = aluval;
    2'h3: mar_next = reg_data_out1;
    default: mar_next = mar;
  endcase
  case (byteenable)
    4'b1111: begin
      writedata = mdr;
      busin_be = readdata;
    end
    4'b0011: begin
      writedata = mdr;
      busin_be = { 16'h0000, readdata[15:0] };
    end 
    4'b1100: begin
      writedata = { mdr[15:0], 16'h0000 };
      busin_be = { 16'h0000, readdata[31:16] };
    end
    4'b0001: begin
      writedata = mdr;
      busin_be = { 24'h000000, readdata[7:0] };
    end
    4'b0010: begin
      writedata = { 16'h0000, mdr[7:0], 8'h00 };
      busin_be = { 24'h000000, readdata[15:8] };
    end
    4'b0100: begin
      writedata = { 8'h00, mdr[7:0], 16'h0000 };
      busin_be = { 24'h000000, readdata[23:16] };
    end
    4'b1000: begin
      writedata = { mdr[7:0], 24'h000000 };
      busin_be = { 24'h000000, readdata[31:24] };
    end
    default: begin // really these are invalid
      writedata = mdr;
      busin_be = readdata;
    end
  endcase
  case (mdrsel)
    4'h0: mdr_next = mdr;
    4'h1: mdr_next = busin_be; // byte aligned
    4'h2: mdr_next = aluval;
    4'h3: mdr_next = reg_data_out1;
    4'h4: mdr_next = intval[31:0];
    4'h5: mdr_next = intval[63:32];
    4'h6: mdr_next = pc;
    4'h7: mdr_next = fp_cvtis_out;
    4'h8: mdr_next = fp_cvtsi_out;
    default: mdr_next = mdr;
  endcase
  case (regsel)
    4'h0: reg_data_in = aluval;
    4'h1: reg_data_in = mdr;
    4'h2: reg_data_in = -reg_data_out2;
    4'h3: reg_data_in = ~reg_data_out2;
    4'h4: reg_data_in = reg_data_out2;
    4'h6: reg_data_in = ir_uval; // no sign ext
    4'h9: reg_data_in = { {24{reg_data_out2[7]}}, reg_data_out2[7:0] };
    4'ha: reg_data_in = { {16{reg_data_out2[15]}}, reg_data_out2[15:0] };
    default: reg_data_in = 0;
  endcase
  case (alu1sel)
    3'h0: alu_in1 = reg_data_out1;
    3'h1: alu_in1 = mar;
    3'h2: alu_in1 = mdr;
    default: alu_in1 = 0;
  endcase
  case (alu2sel)
    3'h0: alu_in2 = reg_data_out2;
    3'h1: alu_in2 = ir_sval;
    3'h2: alu_in2 = 1;
    3'h3: alu_in2 = ir_uval; // prob can remove
    3'h4: alu_in2 = 4;
    3'h5: alu_in2 = mdr;
    default: alu_in2 = 0;
  endcase
  case (int1sel)
    3'h0: int_in1 = reg_data_out1;
    default: int_in1 = reg_data_out1;
  endcase
  case (int2sel)
    3'h0: int_in2 = reg_data_out2;
    3'h1: int_in2 = ir_sval;
    default: int_in2 = reg_data_out2;
  endcase
  case (ccrsel)
    2'h0: ccr_next = ccr;
    2'h1: ccr_next = { alu_carry , 
                       ~(alu_zero | alu_carry),
                       alu_negative ^ alu_overflow,
                       ~(alu_zero | (alu_negative ^ alu_overflow)),
                       alu_zero };
    2'h2: ccr_next = { fp_alb, fp_agb, fp_alb, fp_agb, fp_aeb };
    default: ccr_next = ccr;
  endcase
end

control con0(.clock(clk), .reset_n(reset_n), .ir(ir), .ir_write(ir_write), .ccr(ccr), .ccrsel(ccrsel), .alu_func(alu_func), .alu1sel(alu1sel), .alu2sel(alu2sel),
  .regsel(regsel), .reg_read_addr1(reg_read_addr1), .reg_read_addr2(reg_read_addr2), .reg_write_addr(reg_write_addr), .reg_write(reg_write),
  .mdrsel(mdrsel), .marsel(marsel), .pcsel(pcsel), .int1sel(int1sel), .int2sel(int2sel), .int_func(int_func), .supervisor(super_mode),
  .addrsel(addrsel), .byteenable(byteenable), .bus_read(read), .bus_write(write), .bus_wait(waitrequest), .bus_align(address[1:0]),
  .vectoff_write(vectoff_write), .halt(halt), .exception(exception), .interrupt(interrupt), .int_en(int_en));

alu alu0(.in1(alu_in1), .in2(alu_in2), .func(alu_func), .out(alu_out), .c_out(alu_carry), .n_out(alu_negative), .v_out(alu_overflow), .z_out(alu_zero));
intcalc int0(.clock(clk), .func(int_func), .in1(int_in1), .in2(int_in2), .out(int_out));
fp_cvtis fp_cvtis0(.clock(clk), .dataa(reg_data_out2), .result(fp_cvtis_out));
fp_cvtsi fp_cvtsi0(.clock(clk), .dataa(reg_data_out2), .result(fp_cvtsi_out));
fp_cmp fp_cmp0(.clock(clk), .dataa(reg_data_out1), .datab(reg_data_out2), .aeb(fp_aeb), .agb(fp_agb), .alb(fp_alb));
registerfile intreg(.clk(clk), .rst_n(reset_n), .read1(reg_read_addr1), .read2(reg_read_addr2), .write_addr(reg_write_addr),
  .write_data(reg_data_in), .write_en(reg_write), .data1(reg_data_out1), .data2(reg_data_out2), .supervisor(super_mode));

endmodule
