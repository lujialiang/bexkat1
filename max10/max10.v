module max10(
  input [1:0] raw_clock_50,
  input [9:0] sw,
  input [1:0] key,
  output [9:0] ledr,
  output [7:0] hex0,
  output [7:0] hex1,
  output [7:0] hex2,
  output [7:0] hex3,
  output [7:0] hex4,
  output [7:0] hex5,
  output [12:0] sdram_addrbus,
  inout [15:0] sdram_databus,
  output [1:0] sdram_ba,
  output [1:0] sdram_dqm,
  output sdram_ras_n,
  output sdram_cas_n,
  output sdram_cke,
  output sdram_clk,
  output sdram_we_n,
  output sdram_cs_n,
  input sd_miso,
  output sd_mosi,
  output sd_ss,
  output sd_sclk,
  output rtc_ss,
  output eth_ss,
  output codec_pbdat,
  input codec_reclrc,
  input codec_pblrc,
  input codec_recdat,
  inout codec_sdin,
  inout codec_sclk,
  input codec_bclk,
  output codec_mclk,
  input rtc_miso,
  output rtc_mosi,
  output rtc_sclk,
  output [2:0] matrix0,
  output [2:0] matrix1,
  output matrix_clk,
  output matrix_oe_n,
  output matrix_a, 
  output matrix_b,
  output matrix_c,
  output matrix_stb,
  output serial1_tx,
  input serial1_rx,
  input serial0_rx,
  input serial0_cts,
  output serial0_tx,
  output serial0_rts,
  output vga_hs,
  output vga_vs,
  output reset_n,
  input ard_reset_n,
  output [3:0] vga_r,
  output [3:0] vga_g,
  output [3:0] vga_b,
  input ps2kbd_clk,
  input ps2kbd_data);

// System clock
wire sysclock, locked, rst_i;
wire vga_clock;

assign codec_mclk = 1'b0;

assign reset_n = 1'h1;
assign rst_i = ~locked;

parameter clkfreq = 100000000;
syspll pll0(.inclk0(raw_clock_50[0]), .c0(sysclock), .areset(~ard_reset_n), .c1(vga_clock), .locked(locked));

// SPI wiring
wire [7:0] spi_selects;
wire miso, mosi, sclk;

assign rtc_ss = spi_selects[4];
assign sd_ss = spi_selects[0];
assign sd_mosi = mosi;
assign rtc_mosi = mosi;
assign miso = (~spi_selects[0] ? sd_miso : 1'b0) |
              (~spi_selects[1] ? rtc_miso : 1'b0) |
              (~spi_selects[2] ? rtc_miso : 1'b0) |
              (~spi_selects[3] ? rtc_miso : 1'b0) |
              (~spi_selects[4] ? rtc_miso : 1'b0) |
              (~spi_selects[5] ? rtc_miso : 1'b0);
assign sd_sclk = sclk;
assign rtc_sclk = sclk;
assign eth_ss = 1'b1;

// codec/external I2C
assign codec_sdin = (~i2c_tx ? 1'b0 : 1'bz);
assign codec_sclk = (~i2c_clock ? 1'b0 : 1'bz);

// External SDRAM, SSRAM & flash bus wiring
assign sdram_databus = (sdram_dir ? sdram_dataout : 16'hzzzz);

// System Blinknlights
wire [8:0] sysleds;
assign hex5[7] = ~sysleds[5];
assign hex4[7] = ~sysleds[4];
assign hex3[7] = ~sysleds[3];
assign hex2[7] = ~sysleds[2];
assign hex1[7] = ~sysleds[1];
assign hex0[7] = ~sysleds[0];
assign ledr = { 1'b0, miso, mosi, serial0_tx, serial0_rx, sclk, i2c_clock, ~sd_ss, cpu_halt, cpu_cyc };

// Internal bus wiring
wire [3:0] chipselect;
wire [31:0] cpu_address;
wire [31:0] cpu_readdata, cpu_writedata, matrix_readdata, rom_readdata;
wire [31:0] vect_readdata, io_readdata, sdram_readdata, rom2_readdata;
wire [15:0] sdram_dataout;
wire [3:0] cpu_be, exception;
wire [5:0] io_interrupts;
wire [2:0] cpu_interrupt;
wire cpu_write, cpu_cyc, cpu_ack, cpu_halt;
wire io_ack;
wire rom_read, vect_read;
wire sdram_ack;
wire matrix_read, matrix_write, matrix_ack;
wire int_en, cache_enable, mmu_fault;
wire [1:0] cache_hitmiss;
wire i2c_tx, i2c_clock;
wire accel_tx, accel_clock;
wire sdram_dir;

// only need one cycle for reading onboard memory
reg [1:0] rom_ack, vect_ack;

always @(posedge sysclock or posedge rst_i)
begin
  if (rst_i) begin
    rom_ack <= 2'b0;
    vect_ack <= 2'b0;
  end else begin
    if (chipselect == 4'h0) begin
      rom_ack <= 2'b0;
      vect_ack <= 2'b0;
    end else begin
      rom_ack <= { rom_ack[0], rom_read };
      vect_ack <= { vect_ack[0], vect_read };
    end
  end
end

// interrupt priority encoder
always_comb
begin
  cpu_interrupt = 3'h0;
  if (int_en)
    casex ({ mmu_fault, io_interrupts })
      7'b1xxxxxx: cpu_interrupt = 3'h1; // MMU error
      7'b01xxxxx: cpu_interrupt = 3'h5; // timer3
      7'b001xxxx: cpu_interrupt = 3'h4; // timer2
      7'b0001xxx: cpu_interrupt = 3'h3; // timer1
      7'b00001xx: cpu_interrupt = 3'h2; // timer0
      7'b000001x: cpu_interrupt = 3'h6; // uart0 rx
      7'b0000001: cpu_interrupt = 3'h7; // uart0 tx
      7'b0000000: cpu_interrupt = 3'h0;
    endcase
end

assign cpu_readdata = (chipselect == 4'h1 ? vect_readdata : 32'h0) |
                      (chipselect == 4'h2 ? (sw[9] ? rom2_readdata : rom_readdata) : 32'h0) |
                      (chipselect == 4'h4 ? io_readdata : 32'h0) |
                      (chipselect == 4'h7 ? sdram_readdata : 32'h0) |
                      (chipselect == 4'h6 ? vga_readdata : 32'h0);
assign cpu_ack =  (chipselect == 4'h1 ? vect_ack[1] : 1'h0) |
                  (chipselect == 4'h2 ? rom_ack[1] : 1'h0) |
                  (chipselect == 4'h4 ? io_ack : 1'h0) |
                  (chipselect == 4'h7 ? cpu_gnt & sdram_ack : 1'h0) |
                  (chipselect == 4'h6 ? vga_ack : 1'h0);

assign rom_read = (chipselect == 4'h2 && cpu_cyc && ~cpu_write);
assign vect_read = (chipselect == 4'h1 && cpu_cyc && ~cpu_write);

bexkat2 bexkat0(.clk_i(sysclock), .rst_i(rst_i), .adr_o(cpu_address), .cyc_o(cpu_cyc), .dat_i(cpu_readdata),
  .we_o(cpu_write), .dat_o(cpu_writedata), .sel_o(cpu_be), .ack_i(cpu_ack), .halt(cpu_halt),
  .interrupt(cpu_interrupt), .exception(exception), .int_en(int_en));

mmu mmu0(.adr_i(cpu_address), .cyc_i(cpu_cyc), .chipselect(chipselect), .fault(mmu_fault), .cache_enable(cache_enable));

wire [31:0] fs_adr, vga_address;
wire [31:0] vga_readdata;
wire [3:0] fs_sel, vga_sel;
wire [7:0] r,g,b;

wire td_tx, td_sdat, td_clock, td_sclk;
wire accel_sdat, accel_sclk;

wire vga_we, vga_ack;
wire arb_stb, vga_stb;
wire vga_cyc, arb_cyc, cpu_gnt, vga_gnt;
wire blank_n, fs_we, sync_n;

assign vga_r = (blank_n ? r[7:4] : 4'h0);
assign vga_g = (blank_n ? g[7:4] : 4'h0);
assign vga_b = (blank_n ? b[7:4] : 4'h0);

assign fs_adr = (cpu_gnt ? cpu_address : vga_address);
assign fs_sel = (cpu_gnt ? cpu_be : vga_sel);
assign fs_we = (cpu_gnt ? cpu_write : vga_we);

arbiter arb0(.clk_i(sysclock), .rst_i(rst_i), .cpu_cyc_i(cpu_cyc & (chipselect == 4'h7)),
 .vga_cyc_i(vga_cyc), .cyc_o(arb_cyc), .cpu_gnt(cpu_gnt), .vga_gnt(vga_gnt), .ack_i(sdram_ack));
 
vga_master vga0(.clk_i(sysclock), .rst_i(rst_i), .master_adr_o(vga_address), .master_cyc_o(vga_cyc), .master_dat_i(sdram_readdata),
  .master_we_o(vga_we), .master_sel_o(vga_sel), .master_ack_i(vga_gnt & sdram_ack),
  .slave_adr_i(cpu_address[11:2]), .slave_dat_i(cpu_writedata), .slave_sel_i(cpu_be), .slave_cyc_i(cpu_cyc), .slave_we_i(cpu_write),
  .slave_stb_i(chipselect == 'h6), .slave_ack_o(vga_ack), .slave_dat_o(vga_readdata),
  .vs(vga_vs), .hs(vga_hs), .r(r), .g(g), .b(b), .blank_n(blank_n), .vga_clock(vga_clock), .sync_n(sync_n));
  
sdram_controller_cache #(.width32(1'b0)) sdram0(.clk_i(sysclock), .mem_clk_o(sdram_clk), .rst_i(rst_i), .adr_i(fs_adr[26:2]),
  .dat_i(cpu_writedata), .dat_o(sdram_readdata), .stb_i(cpu_gnt|vga_gnt), .cyc_i(arb_cyc),
  .ack_o(sdram_ack), .sel_i(fs_sel), .we_i(fs_we), .cache_status(cache_hitmiss),
  .we_n(sdram_we_n), .cs_n(sdram_cs_n), .cke(sdram_cke), .cas_n(sdram_cas_n), .ras_n(sdram_ras_n), .dqm(sdram_dqm), .ba(sdram_ba),
  .addrbus_out(sdram_addrbus), .databus_in(sdram_databus), .databus_out(sdram_dataout), .databus_dir(sdram_dir));

iocontroller #(.clkfreq(clkfreq)) io0(.clk_i(sysclock), .rst_i(rst_i), .dat_i(cpu_writedata), .dat_o(io_readdata), .we_i(cpu_write), .adr_i(cpu_address[16:2]),
  .stb_i(chipselect == 4'h4), .cyc_i(cpu_cyc), .ack_o(io_ack), .sel_i(cpu_be),
  .miso(miso), .mosi(mosi), .sclk(sclk), .spi_selects(spi_selects), .interrupts(io_interrupts),
  .rx0(serial0_rx), .tx0(serial0_tx), .rts0(serial0_rts), .cts0(serial0_cts), .tx1(serial1_tx), .rx1(serial1_rx), .sw(sw[7:0]),
  .ps2kbd({ps2kbd_clk, ps2kbd_data}),
  .hex5(hex5[6:0]), .hex4(hex4[6:0]), .hex3(hex3[6:0]), .hex2(hex2[6:0]), .hex1(hex1[6:0]), .hex0(hex0[6:0]),
  .codec_pbdat(codec_pbdat), .codec_recdat(codec_recdat),
  .codec_reclrc(codec_reclrc), .codec_pblrc(codec_pblrc), .led(sysleds),
  .matrix_stb(matrix_stb), .matrix_a(matrix_a), .matrix_b(matrix_b), .matrix_c(matrix_c),
  .matrix0(matrix0), .matrix1(matrix1), .matrix_clk(matrix_clk), .matrix_oe_n(matrix_oe_n),
  .i2c_dataout({accel_tx, td_tx, i2c_tx}), .i2c_datain({accel_sdat, td_sdat, codec_sdin}),
  .i2c_scl({accel_clock, td_clock, i2c_clock}), .i2c_clkin({accel_sclk, td_sclk, codec_sclk}));

monitor rom0(.clock(sysclock), .q(rom_readdata), .rden(rom_read), .address(cpu_address[16:2]));
//testrom rom1(.clock(sysclock), .q(rom2_readdata), .rden(rom_read), .address(cpu_address[12:2]));
vectors vecram0(.clock(sysclock), .q(vect_readdata), .rden(vect_read), .address(cpu_address[6:2]));

endmodule
