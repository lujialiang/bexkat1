module sdram_controller(
  input clk_i,
  output mem_clk_o,
  input rst_i,
  input [24:0] adr_i,
  input [31:0] dat_i,
  output [31:0] dat_o,
  input stb_i,
  input cyc_i,
  output ack_o,
  input [3:0] sel_i,
  input we_i,
  output we_n,
  output cs_n,
  output cke,
  output cas_n,
  output ras_n,
  output reg [3:0] dqm,
  output reg [1:0] ba,
  output reg [12:0] addrbus_out,
  input [31:0] databus_in,
  output reg [31:0] databus_out);

assign {cs_n, cas_n, ras_n, we_n} = cmd;

localparam [3:0] CMD_DESL = 4'hf, CMD_NOP = 4'h7, CMD_READ = 4'h3, CMD_WRITE = 4'h2, CMD_ACTIVATE = 4'h5, CMD_PRECHARGE = 4'h4, CMD_REFRESH = 4'h1,
  CMD_MRS = 4'h0;
localparam [4:0] STATE_INIT_WAIT = 'h0, STATE_INIT_PRECHARGE = 'h1, STATE_INIT_REFRESH1 = 'h2, STATE_INIT_REFRESH1_WAIT = 'h3,
  STATE_INIT_MODE_WAIT = 'h4, STATE_INIT_MODE = 'h5, STATE_IDLE = 'h6, STATE_ACTIVATE = 'h7, STATE_READ = 'h8,
  STATE_READ_WAIT = 'h9, STATE_READ_WAIT2 = 'ha, STATE_REFRESH = 'hb, STATE_READ2 = 'hc, STATE_READ3 = 'hd, STATE_READ4 = 'he,
  STATE_WRITE2 = 'hf, STATE_WRITE3 = 'h10, STATE_WRITE4 = 'h11, STATE_WRITE = 'h12, STATE_WRITE5 = 'h13, STATE_WRITE6 = 'h14,
  STATE_WRITE7 = 'h15;

wire select;

assign mem_clk_o = ~clk_i;
assign ack_o = (state == STATE_READ || state == STATE_READ2 || state == STATE_READ3 || state == STATE_READ4 ||
                state == STATE_WRITE || state == STATE_WRITE2 || state == STATE_WRITE3 || state == STATE_WRITE4);
assign dat_o = (select & ~we_i ? databus_in : 32'h0);
assign cke = ~rst_i;
assign select = cyc_i & stb_i;

reg [1:0] ba_next;
reg [3:0] cmd, cmd_next;
reg [4:0] state, state_next;
reg [15:0] delay, delay_next;
reg [12:0] addrbus_out_next;
reg [3:0] dqm_next;
reg [31:0] databus_out_next;

always @(posedge clk_i or posedge rst_i)
begin
  if (rst_i) begin
    cmd <= CMD_NOP;
    delay <= 16'd20000;
    state <= STATE_INIT_WAIT;
    ba <= 2'b00;
    addrbus_out <= 13'h0000;
    dqm <= 4'hf;
    databus_out <= 32'h0;
  end else begin
    ba <= ba_next;
    cmd <= cmd_next;
    delay <= delay_next;
    state <= state_next;
    addrbus_out <= addrbus_out_next;
    dqm <= dqm_next;
    databus_out <= databus_out_next;
  end
end

always @*
begin
  cmd_next = cmd;
  state_next = state;
  delay_next = delay;
  addrbus_out_next = addrbus_out;
  ba_next = ba;
  dqm_next = dqm;
  databus_out_next = databus_out;
  case (state)
    STATE_INIT_WAIT: begin
      delay_next = delay - 16'h1;
      if (delay == 16'd0) begin
        state_next = STATE_INIT_PRECHARGE;
      end
    end
    STATE_INIT_PRECHARGE: begin
      cmd_next = CMD_PRECHARGE;
      addrbus_out_next[10] = 1'b1; // all banks precharge
      delay_next = delay + 16'h1;
      if (delay == 16'h3) begin
        delay_next = 16'd63;
        state_next = STATE_INIT_REFRESH1;
      end
    end
    STATE_INIT_REFRESH1: begin
      cmd_next = CMD_REFRESH;
      state_next = STATE_INIT_REFRESH1_WAIT;
    end
    STATE_INIT_REFRESH1_WAIT: begin
      cmd_next = CMD_NOP;
      delay_next = delay - 1'b1;
      if (delay == 16'h0)
        state_next = STATE_INIT_MODE;
      else if (delay[2:0] == 3'h0)
        state_next = STATE_INIT_REFRESH1;
    end
    STATE_INIT_MODE: begin
      ba_next = 2'b00;
      cmd_next = CMD_MRS;
      addrbus_out_next = 13'b0000000100010; // CAS = 2, sequential, write/read burst length = 4
      delay_next = 16'h3;
      state_next = STATE_INIT_MODE_WAIT;
    end
    STATE_INIT_MODE_WAIT: begin
      delay_next = delay - 1'b1;
      cmd_next = CMD_NOP;
      if (delay == 16'h0) begin
        cmd_next = CMD_DESL;
        state_next = STATE_IDLE;
      end
    end
    STATE_IDLE: begin
      if (select) begin
        cmd_next = CMD_ACTIVATE; // address[24:0] [24:23] for bank, [22:10] for row, 
        ba_next = adr_i[24:23];
        addrbus_out_next = adr_i[22:10];  // open row
        dqm_next = ~sel_i;
        delay_next = 16'h2;
        state_next = STATE_ACTIVATE;
      end else begin
        cmd_next = CMD_REFRESH;
        addrbus_out_next[10] = 1'b1; // all banks refresh
        delay_next = 16'h6;
        state_next = STATE_REFRESH;
      end
    end
    STATE_REFRESH: begin
      cmd_next = CMD_NOP;
      delay_next = delay - 1'b1;
      if (delay == 16'h0)
        state_next = STATE_IDLE;
    end
    STATE_ACTIVATE: begin
      delay_next = delay - 1'b1;
      if (delay == 16'h0) begin
        cmd_next = (we_i ? CMD_WRITE : CMD_READ);
        ba_next = adr_i[24:23];
        dqm_next = ~sel_i;
        addrbus_out_next[10] = 1'b1; // auto precharge
        addrbus_out_next[9:0] = adr_i[9:0]; // read/write column
        if (we_i) begin
          state_next = STATE_WRITE;
          databus_out_next = dat_i;
        end else begin
          state_next = STATE_READ_WAIT;
        end
      end
    end
    STATE_READ_WAIT: begin
      cmd_next = CMD_NOP;
      state_next = STATE_READ_WAIT2;
    end
    STATE_READ_WAIT2: state_next = STATE_READ;
    STATE_READ: state_next = STATE_READ2;
	 STATE_READ2: state_next = STATE_READ3;
	 STATE_READ3: state_next = STATE_READ4;
	 STATE_READ4: state_next = STATE_IDLE;
    STATE_WRITE: begin
      cmd_next = CMD_NOP;
      state_next = STATE_WRITE2;
    end
	 STATE_WRITE2: state_next = STATE_WRITE3;
	 STATE_WRITE3: state_next = STATE_WRITE4;
	 STATE_WRITE4: state_next = STATE_WRITE5;
	 STATE_WRITE5: state_next = STATE_WRITE6;
	 STATE_WRITE6: state_next = STATE_WRITE7;
	 STATE_WRITE7: state_next = STATE_IDLE;
    default: state_next = STATE_IDLE;
  endcase
end

endmodule
