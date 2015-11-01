module flash_controller(
  input clock,
  input reset_n,
  input [31:0] databus_in,
  output [31:0] databus_out,
  input read,
  input write,
  output wait_out,
  input [15:0] data_in,
  output [15:0] data_out,
  input [3:0] be_in,
  input [25:0] address_in,
  output [26:0] address_out,
  input ready,
  output wp_n,
  output oe_n,
  output we_n,
  output ce_n);

 // This controller will do the work related to page mode reads, etc.
 // the adapt32to16 will adjust for the bus widths by adding an additional bus cycle.
 
adapt32to16 width0(.clock(clock), .reset_n(reset_n), .read(read), .write(write), .data_in(data_in), .data_out(data_out),
  .databus_in(databus_in), .databus_out(databus_out), .ready(ready), .wp_n(wp_n), .ce_n(ce_n), .oe_n(oe_n), .we_n(we_n),
  .address_in(address_in), .address_out(address_out), .wait_out(wait_out), .be_in(be_in));
  
endmodule