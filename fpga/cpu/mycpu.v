module mycpu(clk, rst_n, addrbus, data_in, data_out, write_out, bytectl, ccr, fault);

input clk;
input rst_n;
output [31:0] addrbus;
input [15:0] data_in;
output [15:0] data_out;
output write_out;
output bytectl;
output [3:0] ccr;
output fault;

reg [31:0] pc;
reg [32:0] pc_next;
reg [31:0] mar;
reg [32:0] mar_next;
reg [7:0] state, state_next;
reg [31:0] ir, ir_next;
reg write_out, write_out_next;
reg bytectl, bytectl_next;
reg [31:0] mdr, mdr_next;
reg [3:0] ccr, ccr_next;
reg [7:0] delay, delay_next;
reg addrsel, addrsel_next;
reg mdrsel, mdrsel_next;
reg [31:0] divmul2, divmul2_next;

reg [31:0] alu_in2;
reg [3:0] alu_func;
reg [2:0] int_func;
reg [4:0] reg_read_addr1, reg_read_addr2, reg_write_addr;
reg [1:0] reg_write;

assign fault = (state == STATE_FAULT);
assign data_out = (mdrsel ? mdr[15:0] : mdr[31:16]);
assign addrbus = (addrsel ? mar : pc);

wire data_access;
wire [31:0] reg_data_out1, reg_data_out2, reg_data_in;
wire carry, negative, overflow, zero;
wire alu_carry, alu_negative, alu_overflow, alu_zero;
wire [31:0] alu_out, fp_out, int_out, cvt_int_out, cvt_fp_out;

localparam STATE_FETCHIR1 = 8'h00, STATE_FETCHIR2 = 8'h01, STATE_FETCHIR3 = 8'h02, STATE_EVALIR1 = 8'h03, STATE_EVALIR2 = 8'h04, STATE_EVALIR3 = 8'h05;
localparam STATE_STORE = 8'h06, STATE_STORE2 = 8'h07, STATE_STORE3 = 8'h08;
localparam STATE_LOAD = 8'h09, STATE_LOAD2 = 8'h0a, STATE_LOAD3 = 8'h0b, STATE_LOAD4 = 8'h0c, STATE_FAULT = 8'h0d;
localparam STATE_PUSH = 8'h0f, STATE_PUSH2 = 8'h10, STATE_PUSH3 = 8'h11, STATE_POP = 8'h12, STATE_POP2 = 8'h13, STATE_POP3 = 8'h14, STATE_POP4 = 8'h15;

localparam REG_SP = 5'b11111, REG_FP = 5'b11110;
localparam MDR_HIGH = 1'b0, MDR_LOW = 1'b1;
localparam ADDR_PC = 1'b0, ADDR_MAR = 1'b1;

localparam MODE_INH2 = 3'h0, MODE_IMM3 = 3'h1, MODE_REGIND = 3'h2, MODE_REG = 3'h3, MODE_INH = 3'h4, MODE_IMM2 = 3'h5, MODE_DIR = 3'h6, MODE_IMM3a = 3'h7;

// opcode format
wire [2:0] ir_mode = ir[31:29];
wire [7:0] ir_op   = (ir[31] ? (ir[30:29] == 2'b00 ? { ir[28:26], 5'b00000 } : ir[28:21]) : { ir[28:26], ir[15:11] });
wire [4:0] ir_rb   = ir[25:21];
wire [4:0] ir_rc   = ir[4:0];
wire [4:0] ir_ra   = ir[20:16];

assign {carry, negative, overflow, zero} = ccr;

localparam REG_WRITE_NONE = 2'b00, REG_WRITE_W0 = 2'b01, REG_WRITE_W1 = 2'b10, REG_WRITE_DW = 2'b11;

always @(posedge clk or negedge rst_n)
begin
  if (!rst_n) begin
    pc <= 'hffc00000; // start boot at base of monitor for now
    state <= STATE_FETCHIR1;
    ir <= 'h0000000;
    mdr <= 'h00000000;
    mar <= 'h00000000;
    addrsel <= ADDR_PC;
    mdrsel <= MDR_LOW;
    ccr <= 'h0;
    delay <= 'h0;
    write_out <= 1'b0;
    bytectl <= 1'b0;
    divmul2 <= 'h1;
  end else begin
    pc <= pc_next[31:0];
    state <= state_next;
    delay <= delay_next;
    ir <= ir_next;
    mdr <= mdr_next;
    mar <= mar_next[31:0];
    addrsel <= addrsel_next;
    mdrsel <= mdrsel_next;
    ccr <= ccr_next;
    write_out <= write_out_next;
    bytectl <= bytectl_next;
    divmul2 <= divmul2_next;
  end
end

always @*
begin
  pc_next = pc;
  state_next = state;
  delay_next = delay;
  ir_next = ir;
  mdr_next = mdr;
  write_out_next = write_out;
  mar_next = mar;
  addrsel_next = addrsel;
  mdrsel_next = mdrsel;
  ccr_next = ccr;
  bytectl_next = bytectl;
  divmul2_next = divmul2;
  
  // Control signals we need to deal with
  alu_func = 4'h2; // add is default
  int_func = 3'b000;
  reg_read_addr1 = ir_ra;
  reg_read_addr2 = ir_rb;
  reg_write_addr = ir_ra;
  reg_data_in = alu_out;
  reg_write = REG_WRITE_NONE;
  alu_in2 = 'h2;
  case (state)
    STATE_FETCHIR1: begin
      if (delay == 'h0) begin
        addrsel_next = ADDR_PC;
        write_out_next = 1'b0;
        bytectl_next = 1'b0;
        delay_next = 'h4;
      end else begin
        delay_next = delay - 3'b1;
        if (delay == 'h1) begin
          ir_next = { data_in, 16'h0000 };
          pc_next = pc + 'h2;
          state_next = STATE_EVALIR1;
        end
      end      
    end
    STATE_EVALIR1: begin
      casex ({ir_mode, ir_op})
        {MODE_INH, 8'h0x}: state_next = STATE_FETCHIR1; // nop
        {MODE_INH, 8'h2x}: begin // rts
          state_next = STATE_POP;
          reg_read_addr1 = REG_SP;
          reg_write = REG_WRITE_DW;
          reg_write_addr = REG_SP;
          addrsel_next = ADDR_MAR;
          mar_next = reg_data_out1;
        end
        {MODE_INH, 8'h4x}: begin // cmp
          alu_func = 'h3; // sub
          alu_in2 = reg_data_out2;
          if (delay == 'h0) begin
            delay_next = 'h2;
          end else begin
            delay_next = delay - 1'b1;
            if (delay == 'h1) begin
              ccr_next = {alu_carry, alu_negative, alu_overflow, alu_zero};
              state_next = STATE_FETCHIR1;
            end
          end
        end
        {MODE_INH, 8'h6x}: begin // inc rA
          alu_in2 = 'h1;
          reg_write = REG_WRITE_DW;
          state_next = STATE_FETCHIR1;
        end
        {MODE_INH, 8'h8x}: begin // dec rA
          alu_func = 'h3; // sub
          alu_in2 = 'h1;
          reg_write = REG_WRITE_DW;
          state_next = STATE_FETCHIR1;
        end
        {MODE_INH, 8'hax}: begin // push rA
          state_next = STATE_PUSH;
          reg_read_addr1 = REG_SP;
          alu_func = 'h3; // sub
          reg_write = REG_WRITE_DW;
          reg_write_addr = REG_SP;
          mar_next = alu_out;
          addrsel_next = ADDR_MAR;          
          reg_read_addr2 = ir_ra;
          mdr_next = reg_data_out2;
          mdrsel_next = MDR_LOW;
          write_out_next = 1'b1;
        end
        {MODE_INH, 8'hcx}: begin // pop rA
          state_next = STATE_POP;
          reg_read_addr1 = REG_SP;
          reg_write = REG_WRITE_DW;
          reg_write_addr = REG_SP;
          addrsel_next = ADDR_MAR;
          mar_next = reg_data_out1;
        end
        {MODE_INH, 8'hex}: begin // mov
          state_next = STATE_FETCHIR1;
          reg_read_addr1 = ir_rb;
          reg_data_in = reg_data_out1;
          reg_write = REG_WRITE_DW;
        end
        default: state_next = STATE_FETCHIR2;
      endcase
    end
    STATE_FETCHIR2: begin
      if (delay == 'h0) begin
        addrsel_next = ADDR_PC;
        write_out_next = 1'b0;
        delay_next = 'h4;
      end else begin
        delay_next = delay - 3'b1;
        if (delay == 'h1) begin
          case (ir_mode)
            MODE_IMM2  : begin
              mar_next = { {16{data_in[15]}},data_in };
              mdr_next = { 16'h0000, data_in };
            end
            MODE_REGIND: begin
              mar_next = { {21{data_in[10]}}, data_in[10:0] };
              ir_next[15:0] = data_in;
            end
            MODE_DIR   : mar_next = { 16'h0000, data_in };
            MODE_IMM3a : mdr_next = { 16'h0000, data_in };
            default    : ir_next[15:0] = data_in;
          endcase
          pc_next = pc + 'h2;
          state_next = STATE_EVALIR2;
        end
      end      
    end
    STATE_EVALIR2: begin
      casex ({ir_mode, ir_op})
        {MODE_INH2, 8'bxx0xxx1x}: begin // com
          state_next = STATE_FETCHIR1;
          reg_read_addr1 = ir_rb;
          reg_data_in = ~reg_data_out1;
          reg_write = REG_WRITE_DW;
        end
        {MODE_INH2, 8'bxx1xxx1x}: begin // neg
          state_next = STATE_FETCHIR1;
          reg_read_addr1 = ir_rb;
          reg_data_in = -reg_data_out1;
          reg_write = REG_WRITE_DW;
        end
        {MODE_IMM2, 8'bxxx1xxx0}: begin // ldis
          reg_data_in = mar;
          reg_write = REG_WRITE_DW;
          state_next = STATE_FETCHIR1;
        end
        {MODE_IMM2, 8'bxxx1xxx1}: begin // ldiu
          reg_data_in = mdr;
          reg_write = REG_WRITE_DW;
          state_next = STATE_FETCHIR1;
        end
        {MODE_IMM2, 8'bxxx00000}: begin // bra
          state_next = STATE_FETCHIR1;
          pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx00001}: begin // beq
          state_next = STATE_FETCHIR1;
          if (zero)
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx00010}: begin // bne
          state_next = STATE_FETCHIR1;
          if (~zero)
            pc_next = { 1'b0, pc } + mar;        
        end
        {MODE_IMM2, 8'bxxx00011}: begin // bgtu
          state_next = STATE_FETCHIR1;
          if (~(zero | carry))
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx00100}: begin // bgt
          state_next = STATE_FETCHIR1;
          if (~(zero | (negative ^ overflow)))
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx00101}: begin // bge
          state_next = STATE_FETCHIR1;
          if (~(negative ^ overflow))
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx00110}: begin // ble
          state_next = STATE_FETCHIR1;
          if (zero | (negative ^ overflow))
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx00111}: begin // blt
          state_next = STATE_FETCHIR1;
          if (negative ^ overflow)
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx01000}: begin // bgeu
          state_next = STATE_FETCHIR1;
          if (~carry)
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx01001}: begin // bltu
          state_next = STATE_FETCHIR1;
          if (carry)
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx01010}: begin // bleu
          state_next = STATE_FETCHIR1;
          if (carry | zero)
            pc_next = { 1'b0, pc } + mar;
        end
        {MODE_IMM2, 8'bxxx01011}: begin // brn
          state_next = STATE_FETCHIR1;
        end
        {MODE_REG, 8'bxx0xxxxx}: begin // alu rA <= rB + rC
          alu_func = ir_op[3:0];
          reg_read_addr1 = ir_rb;
          reg_read_addr2 = ir_rc;
          alu_in2 = reg_data_out2;
          reg_write = REG_WRITE_DW;
          state_next = STATE_FETCHIR1;
        end
        {MODE_REG, 8'bxx1xxxxx}: begin // [un]signed rA <= rB * / % rC
          case (ir_op)
            'h29: int_func = 'b001;
            'h2a: int_func = 'b010;
            'h2b: int_func = 'b100;
            'h2c: int_func = 'b101;
            'h2d: int_func = 'b110;
            default: int_func = 'b000;
          endcase
          reg_read_addr1 = ir_rb;
          reg_read_addr2 = ir_rc;
          divmul2_next = reg_data_out2;
          if (delay == 'h0) begin
            delay_next = 'h7;
          end else begin
            delay_next = delay - 1'b1;
            if (delay == 'h1) begin
              reg_data_in = int_out;
              reg_write = REG_WRITE_DW;
              state_next = STATE_FETCHIR1;
            end
          end
        end
        {MODE_REGIND, 8'h00}: begin // st.l
            state_next = STATE_STORE;
            reg_read_addr1 = ir_rb;
            alu_in2 = mar;
            mar_next = alu_out;
            addrsel_next = ADDR_MAR;
            reg_read_addr2 = ir_ra;
            mdr_next = reg_data_out2;
            mdrsel_next = MDR_HIGH;
            write_out_next = 1'b1;
        end
        {MODE_REGIND, 8'h01}: begin // ld.l
            state_next = STATE_LOAD;
            reg_read_addr1 = ir_rb;
            alu_in2 = mar;
            mar_next = alu_out;
            addrsel_next = ADDR_MAR;
        end
        {MODE_REGIND, 8'h02}: begin // st
            state_next = STATE_STORE;
            reg_read_addr1 = ir_rb;
            alu_in2 = mar;
            mar_next = alu_out;
            addrsel_next = ADDR_MAR;
            mdrsel_next = MDR_LOW;
            reg_read_addr2 = ir_ra;
            mdr_next = reg_data_out2;
            write_out_next = 1'b1;
        end
        {MODE_REGIND, 8'h03}: begin // ld
            state_next = STATE_LOAD;
            reg_read_addr1 = ir_rb;
            alu_in2 = mar;
            mar_next = alu_out;
            addrsel_next = ADDR_MAR;
        end
        {MODE_REGIND, 8'h04}: begin // st.b
            state_next = STATE_STORE;
            reg_read_addr1 = ir_rb;
            alu_in2 = mar;
            mar_next = alu_out;
            addrsel_next = ADDR_MAR;
            reg_read_addr2 = ir_ra;
            if (alu_out[0])
              mdr_next[7:0] = reg_data_out2[7:0];
            else
              mdr_next[15:8] = reg_data_out2[7:0];
            mdrsel_next = MDR_LOW;
            write_out_next = 1'b1;
            bytectl_next = 1'b1;
        end
        {MODE_REGIND, 8'h05}: begin // ld.b
            state_next = STATE_LOAD;
            reg_read_addr1 = ir_rb;
            alu_in2 = mar;
            mar_next = alu_out;
            mdrsel_next = MDR_LOW;
            addrsel_next = ADDR_MAR;
        end
        {MODE_REGIND, 8'h0a}: begin // lda
          state_next = STATE_FETCHIR1;
          reg_read_addr1 = ir_rb;
          alu_in2 = mar;
          reg_write = REG_WRITE_DW;
        end
        {MODE_REGIND, 8'ha0}: begin // jmp
          state_next = STATE_FETCHIR1;
          reg_read_addr1 = ir_rb;
          alu_in2 = mar;
          pc_next = { 1'b0, alu_out};
        end
        {MODE_REGIND, 8'ha1}: begin // jsr
          state_next = STATE_FAULT;
          // Can't really do two ALU ops at once, both the relative computation of the new PC
          // and the setup for the SP and PUSH op.
        end
        default: state_next = STATE_FETCHIR3;
      endcase
    end
    STATE_FETCHIR3: begin
      if (delay == 'h0) begin
        addrsel_next = ADDR_PC;
        write_out_next = 1'b0;
        delay_next = 'h4;
      end else begin
        delay_next = delay - 3'b1;
        if (delay == 'h1) begin
          case (ir_mode)
            MODE_DIR: mar_next = { mar[15:0], data_in };
            default: mdr_next = { mdr[15:0], data_in }; 
          endcase
          pc_next = pc + 'h2;
         state_next = STATE_EVALIR3;
        end
      end      
    end
    STATE_EVALIR3: begin
      casex ({ir_mode, ir_op})
        {MODE_IMM3, 8'h0x}: begin // alu rA <= rB + 0xabcd
          alu_func = ir_op[3:0];
          reg_read_addr1 = ir_rb;
          alu_in2 = { {16{mdr[15]}}, mdr[15:0] };
          reg_write = REG_WRITE_DW;
          state_next = STATE_FETCHIR1;
        end
        {MODE_IMM3, 8'h2x}: begin // [un]signed rA <= rB * / % 0xabcd
          case (ir_op)
            'h29: int_func = 'b001;
            'h2a: int_func = 'b010;
            'h2b: int_func = 'b100;
            'h2c: int_func = 'b101;
            'h2d: int_func = 'b110;
            default: int_func = 'b000;
          endcase
          reg_read_addr1 = ir_rb;
          divmul2_next = { {16{mdr[15]}}, mdr[15:0] };
          if (delay == 'h0) begin
            delay_next = 'h7;
          end else begin
            delay_next = delay - 1'b1;
            if (delay == 'h1) begin
              reg_data_in = int_out;
              reg_write = REG_WRITE_DW;
              state_next = STATE_FETCHIR1;
            end
          end
        end
        {MODE_IMM3a, 8'h00}: begin // ldi
          state_next = STATE_FETCHIR1;
          reg_data_in = mdr;
          reg_write = REG_WRITE_DW;        
        end
        {MODE_DIR, 8'h00}: begin // std.l
          state_next = STATE_STORE;
          mdr_next = reg_data_out1;
          mdrsel_next = MDR_HIGH;
          addrsel_next = ADDR_MAR;
          write_out_next = 1'b1;
        end
        {MODE_DIR, 8'h01}: begin // ldd.l
          state_next = STATE_LOAD;
          addrsel_next = ADDR_MAR;
        end
        {MODE_DIR, 8'h02}: begin // std
          state_next = STATE_STORE;
          mdr_next = reg_data_out1;
          mdrsel_next = MDR_LOW;
          addrsel_next = ADDR_MAR;
          write_out_next = 1'b1;
        end
        {MODE_DIR, 8'h03}: begin // ldd
          state_next = STATE_LOAD;
          addrsel_next = ADDR_MAR;
        end
        {MODE_DIR, 8'h04}: begin // std.b
          state_next = STATE_STORE;
          if (alu_out[0])
            mdr_next[7:0] = reg_data_out1[7:0];
          else
            mdr_next[15:8] = reg_data_out1[7:0];
          mdrsel_next = MDR_LOW;
          addrsel_next = ADDR_MAR;
          write_out_next = 1'b1;
          bytectl_next = 1'b1;
        end
        {MODE_DIR, 8'h05}: begin // ldd.b
          state_next = STATE_LOAD;
          addrsel_next = ADDR_MAR;
        end
        {MODE_DIR, 8'h80}: begin // jmpd
          state_next = STATE_FETCHIR1;
          pc_next = { 1'b0, mar};
        end
        {MODE_DIR, 8'h81}: begin // jsrd
          state_next = STATE_PUSH;
          reg_read_addr1 = REG_SP;
          alu_func = 'h3; // sub
          reg_write = REG_WRITE_DW;
          reg_write_addr = REG_SP;
          mar_next = alu_out;
          mdr_next = pc;
          pc_next = mar;
          mdrsel_next = MDR_LOW;
          addrsel_next = ADDR_MAR;          
          write_out_next = 1'b1;        
        end
        default: state_next = STATE_FAULT;
      endcase 
    end
    STATE_STORE: begin
      write_out_next = 1'b0;
      bytectl_next = 1'b0;
      mdrsel_next = MDR_LOW;
      case (ir_op[3:1])
        'h0: begin
          state_next = STATE_STORE2;
        end
        'h1: state_next = STATE_FETCHIR1;
        'h2: state_next = STATE_FETCHIR1;
        default: state_next = STATE_FAULT;
      endcase
    end
    STATE_STORE2: begin
      state_next = STATE_STORE3;
      mar_next = mar + 'h2;
      write_out_next = 1'b1;
    end
    STATE_STORE3: begin
      state_next = STATE_FETCHIR1;
      addrsel_next = ADDR_PC;
      write_out_next = 1'b0;
    end
    STATE_LOAD: state_next = STATE_LOAD2;
    STATE_LOAD2: begin
      case (ir_op[3:1])
        'h0: begin
          state_next = STATE_LOAD3;
          reg_data_in = { data_in, 16'h0000 };
          reg_write = REG_WRITE_DW;
          mar_next = mar + 'h2;
        end
        'h1: begin
          state_next = STATE_FETCHIR1;
          addrsel_next = ADDR_PC;
          reg_data_in = { 16'h0000, data_in };
          reg_write = REG_WRITE_DW;
        end
        'h2: begin
          state_next = STATE_FETCHIR1;
          addrsel_next = ADDR_PC;
          reg_data_in = { 24'h000000, (mar[0] ? data_in[7:0] : data_in[15:8]) };
          reg_write = REG_WRITE_DW;
        end 
        default: state_next = STATE_FAULT;
      endcase
    end
    STATE_LOAD3: state_next = STATE_LOAD4;
    STATE_LOAD4: begin
      state_next = STATE_FETCHIR1;
      addrsel_next = ADDR_PC;
      reg_data_in = { 16'h0000, data_in };
      reg_write = REG_WRITE_W0;
    end
    STATE_POP: state_next = STATE_POP2;
    STATE_POP2: begin
      state_next = STATE_POP3;
      reg_read_addr1 = REG_SP;
      mar_next = reg_data_out1;
      case ({ir_mode, ir_op})
        {MODE_INH, 8'hc0}: begin // pop
          reg_data_in = { data_in, 16'h0000 };
          reg_write = REG_WRITE_W1;
        end
        default: pc_next[31:16] = data_in;
      endcase
    end
    STATE_POP3: begin
      state_next = STATE_POP4;
      reg_read_addr1 = REG_SP;
      reg_write = REG_WRITE_DW;
      reg_write_addr = REG_SP;
    end
    STATE_POP4: begin
      state_next = STATE_FETCHIR1;
      case ({ir_mode, ir_op})
        {MODE_INH, 8'hc0}: begin // pop
          reg_data_in = { 16'h0000, data_in };
          reg_write = REG_WRITE_W0;
        end
        default: pc_next[15:0] = data_in;
      endcase
      addrsel_next = ADDR_PC;      
    end
    STATE_PUSH: begin
      state_next = STATE_PUSH2;
      write_out_next = 1'b0;
    end
    STATE_PUSH2: begin
      state_next = STATE_PUSH3;
      write_out_next = 1'b1;
      reg_read_addr1 = REG_SP;
      alu_func = 'h3; // sub
      reg_write = REG_WRITE_DW;
      reg_write_addr = REG_SP;
      mar_next = alu_out;
      mdrsel_next = MDR_HIGH;
    end
    STATE_PUSH3: begin
      state_next = STATE_FETCHIR1;
      write_out_next = 1'b0;
      addrsel_next = ADDR_PC;
    end
    STATE_FAULT: state_next = STATE_FAULT;
  endcase
end

alu alu0(.in1(reg_data_out1), .in2(alu_in2), .func(alu_func), .out(alu_out), .c_out(alu_carry), .n_out(alu_negative), .v_out(alu_overflow), .z_out(alu_zero));
intcalc int0(.clock(clk), .func(int_func), .in1(reg_data_out1), .in2(divmul2), .out(int_out));
registerfile intreg(.clk(clk), .rst_n(rst_n), .read1(reg_read_addr1), .read2(reg_read_addr2), .write_addr(reg_write_addr),
  .write_data(reg_data_in), .write_en(reg_write), .data1(reg_data_out1), .data2(reg_data_out2));
  
endmodule
