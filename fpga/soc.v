`include "../../fpgalib/bexkat1/exceptions.vh"

module soc(input 	 raw_clock_50,
	   input [17:0]  SW,
	   input [3:0] 	 KEY,
	   output [8:0]  LEDG,
	   output [17:0] LEDR,
	   output [6:0]  HEX0,
	   output [6:0]  HEX1,
	   output [6:0]  HEX2,
	   output [6:0]  HEX3,
	   output [6:0]  HEX4,
	   output [6:0]  HEX5,
	   output [6:0]  HEX6,
	   output [6:0]  HEX7,
	   output [12:0] sdram_addrbus,
	   inout [31:0]  sdram_databus,
	   output [1:0]  sdram_ba,
	   output [3:0]  sdram_dqm,
	   output 	 sdram_ras_n,
	   output 	 sdram_cas_n,
	   output 	 sdram_cke,
	   output 	 sdram_clk,
	   output 	 sdram_we_n,
	   output 	 sdram_cs_n,
	   output 	 lcd_e,
	   output 	 lcd_rs,
	   output 	 lcd_on,
	   output 	 lcd_rw,
	   inout [7:0] 	 lcd_data,
	   input 	 sd_miso,
	   output 	 sd_mosi,
	   output 	 sd_ss,
	   output 	 sd_sclk,
	   input 	 ext_miso,
	   output 	 ext_mosi,
	   output 	 ext_sclk,
	   output 	 rtc_ss,
	   output 	 led_ss,
	   input 	 sd_wp_n,
	   output 	 fan_ctrl, 
	   output [2:0]  matrix0,
	   output [2:0]  matrix1,
	   output 	 matrix_clk,
	   output 	 matrix_oe_n,
	   output 	 matrix_a, 
	   output 	 matrix_b,
	   output 	 matrix_c,
	   output 	 matrix_stb,
	   output 	 serial1_tx,
	   input 	 serial1_rx,
	   output 	 serial2_tx,
	   input 	 serial2_rx,
	   input 	 serial2_cts,
	   output 	 serial2_rts,
	   input 	 serial0_rx,
	   input 	 serial0_cts,
	   output 	 serial0_tx,
	   output 	 serial0_rts,
	   output 	 vga_hs,
	   output 	 vga_vs,
	   output 	 vga_blank_n,
	   output 	 vga_sync_n,
	   output 	 vga_clock,
	   output [7:0]  vga_r,
	   output [7:0]  vga_g,
	   output [7:0]  vga_b,
	   input 	 ps2kbd_clk,
	   input 	 ps2kbd_data,
	   output 	 reset_n);

  // System clock
  logic 		 sysclock, rst_i, locked;
  
  if_wb ins_bus();
  if_wb dat_bus();
  if_wb iobus();
  if_wb rambus();
  if_wb rombus0();
  if_wb rombus1();
  if_wb vectbus0();
  if_wb vectbus1();
  
  assign reset_n = KEY[1];
  assign rst_i = ~locked;
  
  parameter clkfreq = 1000000;
  
  sysclock pll0(.inclk0(raw_clock_50), .c0(sysclock), .areset(~KEY[0]), .c1(vga_clock), .locked(locked));
  
  // SPI wiring
  logic [7:0] 		 spi_selects;
  logic 		 miso, mosi, sclk;
  
  assign rtc_ss = spi_selects[4];
  assign led_ss = spi_selects[1];
  assign sd_ss = spi_selects[0];
  assign sd_mosi = mosi;
  assign ext_mosi = mosi;
  assign miso = (~spi_selects[0] ? sd_miso : 1'b0) |
		(~spi_selects[1] ? ext_miso : 1'b0) |
		(~spi_selects[2] ? ext_miso : 1'b0) |
		(~spi_selects[3] ? ext_miso : 1'b0) |
		(~spi_selects[4] ? ext_miso : 1'b0) |
		(~spi_selects[5] ? ext_miso : 1'b0);
  assign sd_sclk = sclk;
  assign ext_sclk = sclk;
  
  // LCD wiring
  assign lcd_data = (lcd_rw ? 8'hzz : lcd_dataout);
  
  // External SDRAM, SSRAM & flash bus wiring
  assign sdram_databus = (sdram_dir ? sdram_dataout : 32'hzzzzzzzz);
   
  // System Blinknlights
  assign LEDR[7] = rambus.stb;
  assign LEDR[6] = rombus1.stb;
  assign LEDR[5] = rombus0.stb;  
  assign LEDR[4] = iobus.stb;
  assign LEDR[3:0] = cpu_interrupt;
  assign LEDG[8] = cpu_halt;
  assign LEDG[7:5] = { dat_bus.cyc, dat_bus.stb, dat_bus.ack };
  assign LEDG[4:2] = { ins_bus.cyc, ins_bus.stb, ins_bus.ack };
  assign LEDG[1:0] = cache_hitmiss;

  // Internal bus wiring
  logic [31:0] 		 sdram_dataout;
  logic [3:0] 		 exception;
  logic [5:0] 		 io_interrupts;
  logic [3:0] 		 cpu_interrupt;
  logic [7:0] 		 lcd_dataout;
  logic 		 cpu_halt;
  logic 		 supervisor;
  logic [3:0] 		 sdram_den_n;
  logic 		 int_en;
  logic 		 insmmu_fault, datmmu_fault, mmu_fault;
  logic [1:0] 		 cache_hitmiss;
  logic 		 sdram_dir;

  always mmu_fault = insmmu_fault | datmmu_fault;
  
  // interrupt priority encoder
  always_comb
    begin
      cpu_interrupt = 4'h0;
      if (int_en)
	casex ({ mmu_fault, io_interrupts })
	  7'b1xxxxxx: cpu_interrupt = EXC_MMU;
	  7'b01xxxxx: cpu_interrupt = EXC_TIMER3;
	  7'b001xxxx: cpu_interrupt = EXC_TIMER2;
	  7'b0001xxx: cpu_interrupt = EXC_TIMER1;
	  7'b00001xx: cpu_interrupt = EXC_TIMER0;
	  7'b000001x: cpu_interrupt = EXC_UART0_RX;
	  7'b0000001: cpu_interrupt = EXC_UART0_TX;
	  7'b0000000: cpu_interrupt = EXC_RESET;
	endcase
    end
 
  bexkat1p cpu0(.clk_i(sysclock), .rst_i(rst_i),
		.halt(cpu_halt),
		.inter(cpu_interrupt[2:0]),
		.exception(exception),
		.supervisor(supervisor),
		.int_en(int_en),
		.ins_bus(ins_bus.master),
		.dat_bus(dat_bus.master));
 
  mmu ins_mmu0(.clk_i(sysclock), .rst_i(rst_i),
	       .cpubus(ins_bus.slave),
	       .rombus(rombus0.master),
	       .vectbus(vectbus0.master),
	       .supervisor(supervisor),
	       .fault(insmmu_fault));
  mmu dat_mmu0(.clk_i(sysclock), .rst_i(rst_i),
	       .cpubus(dat_bus.slave),
	       .iobus(iobus.master),
	       .rombus(rombus1.master),
	       .rambus(rambus.master),
	       .vectbus(vectbus1.master),
	       .supervisor(supervisor),
	       .fault(datmmu_fault));

wbmem wbram(.clk_i(sysclock), .rst_i(rst_i),
	    .bus(rambus.slave));
  
/*  
  sdram_controller_cache sdram0(.clk_i(sysclock),
				.mem_clk_o(sdram_clk),
				.rst_i(rst_i),
				.bus(rambus.slave),
				.stats_stb_i(1'b0),
				.cache_status(cache_hitmiss),
				.we_n(sdram_we_n),
				.cs_n(sdram_cs_n),
				.cke(sdram_cke),
				.cas_n(sdram_cas_n),
				.ras_n(sdram_ras_n),
				.dqm(sdram_dqm),
				.ba(sdram_ba),
				.addrbus_out(sdram_addrbus),
				.databus_in(sdram_databus),
				.databus_out(sdram_dataout),
				.databus_dir(sdram_dir));
  */
  iocontroller
    #(.clkfreq(clkfreq)) io0(.clk_i(sysclock),
			     .rst_i(rst_i),
			     .bus(iobus.slave),
			     .miso(miso),
			     .mosi(mosi),
			     .sclk(sclk),
			     .spi_selects(spi_selects),
			     .sd_wp(sd_wp_n),
			     .lcd_e(lcd_e),
			     .lcd_data(lcd_dataout),
			     .lcd_rs(lcd_rs),
			     .lcd_on(lcd_on),
			     .lcd_rw(lcd_rw),
			     .interrupts(io_interrupts),
			     .rx0(serial0_rx),
			     .tx0(serial0_tx),
			     .rts0(serial0_rts), 
			     .cts0(serial0_cts),
			     .tx1(serial1_tx),
			     .rx1(serial1_rx),
			     .tx2(serial2_tx),
			     .rx2(serial2_rx),
			     .rts2(serial2_rts),
			     .cts2(serial2_cts),
			     .sw(SW[15:0]),
			     .ps2kbd({ps2kbd_clk, ps2kbd_data}),
			     .hex7(HEX7),
			     .hex6(HEX6),
			     .hex5(HEX5),
			     .hex4(HEX4),
			     .hex3(HEX3),
			     .hex2(HEX2),
			     .hex1(HEX1),
			     .hex0(HEX0),
			     .matrix_a(matrix_a),
			     .matrix_b(matrix_b),
			     .matrix_c(matrix_c),
			     .matrix_stb(matrix_stb),
			     .matrix_oe_n(matrix_oe_n),
			     .matrix_clk(matrix_clk),
			     .matrix0(matrix0),
			     .matrix1(matrix1));
  
  bios bios0(.clk_i(sysclock),
	     .rst_i(rst_i),
	     .rombus0(rombus0.slave),
	     .rombus1(rombus1.slave),
	     .vectbus0(vectbus0.slave),
	     .vectbus1(vectbus1.slave),
	     .select(SW[17]));
  
  /*
   logic [21:0] vga_mem_addr;
   logic 	vga_mem_cyc, vga_mem_we, vga_mem_stb;
   logic [31:0] vga_mem_dat_i, vga_mem_dat_o;
   logic [3:0] 	vga_mem_sel;
   
   ssram_controller ram1(.clk_i(sysclock),
			 .rst_i(rst_i),
			 .cyc_i(vga_mem_cyc),
			 .we_i(vga_mem_we),
			 .stb_i(vga_mem_stb),
			 .dat_i(vga_mem_dat_o),
			 .dat_o(vga_mem_dat_i),
			 .sel_i(vga_mem_sel),
			 .adr_i(vga_mem_addr),
			 .databus_in(fs_databus),
			 .databus_out(ssram_dataout),
			 .address_out(ssram_addrout), 
			 .gw_n(ssram_gw_n),
			 .adv_n(ssram_adv_n),
			 .adsp_n(ssram_adsp_n),
			 .adsc_n(ssram_adsc_n),
			 .be_out(ssram_be),
			 .oe_n(ssram_oe_n),
			 .we_n(ssram_we_n),
			 .ce0_n(ssram0_ce_n),
			 .ce1_n(ssram1_ce_n),
			 .bus_clock(ssram_clk));
   
   vga_master video0(.clk_i(sysclock),
		     .rst_i(rst_i),
		     .slave_cyc_i(cpu_cyc),
		     .slave_ack_o(vga_ack),
		     .slave_we_i(cpu_write),
		     .slave_sel_i(cpu_be),
		     .slave_adr_i(cpu_address),
		     .slave_dat_i(cpu_writedata),
		     .slave_dat_o(vga_readdata),
		     .slave_stb_i(chipselect == 4'h6), 
		     .vs(vga_vs),
		     .hs(vga_hs),
		     .r(vga_r),
		     .g(vga_g),
		     .b(vga_b),
		     .blank_n(vga_blank_n),
		     .vga_clock(vga_clock),
		     .sync_n(vga_sync_n),
		     .master_adr_o(vga_mem_addr),
		     .master_cyc_o(vga_mem_cyc),
		     .master_we_o(vga_mem_we),
		     .master_stb_o(vga_mem_stb),
		     .master_sel_o(vga_mem_sel),
		     .master_dat_o(vga_mem_dat_o),
		     .master_dat_i(vga_mem_dat_i));
    */
endmodule
