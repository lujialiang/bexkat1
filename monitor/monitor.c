#include "misc.h"
#include "matrix.h"
#include "serial.h"

unsigned int addr;
unsigned short data;

volatile unsigned int *vga = (unsigned int *)0x00c00000;

void serial_srec(unsigned port);
void vga_test();

char helpmsg[] = "\n? = help\np hhhh = set high address page\nr llll xx = read xx bytes of page hhhh llll and display\nw llll xx = write byte xx to location hhhh llll\ns = s-record upload\n\n";

void vga_test() {
  unsigned i;

  for (i=0; i < 640*480; i++) {
    vga[i] = 0;
  }
  vga[0] = 0xff0000;
  vga[1] = 0xff00;
  vga[2] = 0xff;
  vga[10] = 0xa0;
  vga[639] = 0xa000;
  vga[640] = 0xa00000;
  vga[240*640+320] = 0xb0b0b0;
}

void serial_srec(unsigned port) {
  unsigned short done = 0;
  char c;
  unsigned char len;
  char type;
  unsigned char sum;
  unsigned short pos;
  char *s;

  while (!done && (serial_getchar(port) == 'S')) {
    type = serial_getchar(port);
    switch (type) {
    case '0':
      len = hextoi(serial_getchar(port));
      len = (len << 4) + hextoi(serial_getchar(port));
      sum = len;
      while (len != 0) {
	c = hextoi(serial_getchar(port));
	c = (c << 4) + hextoi(serial_getchar(port));
	sum += c;
	serial_printhex(port, sum);
	serial_putchar(port, '\n');
	len--;
      }
      if (sum != 0xff) {
	done = 1;
	serial_print(0, "checksum fail!?\n");
        matrix[pos++] = 0xff0000;
      } else {
  	matrix[pos++] = 0xff00;
      }
    break;
    case '1':
      len = hextoi(serial_getchar(port));
      len = (len << 4) + hextoi(serial_getchar(port));
      sum = 0;
      break;
    case '2':
      len = hextoi(serial_getchar(port));
      len = (len << 4) + hextoi(serial_getchar(port));
      sum = 0;
      break;
    case '3':
      len = hextoi(serial_getchar(port));
      len = (len << 4) + hextoi(serial_getchar(port));
      sum = 0;
      break;
    case '9':
      done = 1;
      break;
    case '8':
      done = 1;
      break;
    case '7':
      done = 1;
      break;
    }
  }
}

void serial_dumpmem(unsigned port,
		    unsigned addr, 
		    unsigned short len) {
  unsigned int i;
  unsigned *pos = (unsigned *)addr;
  
  serial_print(port, "\n");
  for (i=0; i < len; i += 4) {
    serial_printhex(port, addr+4*i);
    serial_print(port, ": ");
    serial_printhex(port, pos[i]);
    serial_print(port, " ");
    serial_printhex(port, pos[i+1]);
    serial_print(port, " ");
    serial_printhex(port, pos[i+2]);
    serial_print(port, " ");
    serial_printhex(port, pos[i+3]);
    serial_print(port, "\n");
  }
}

void main(void) {
  unsigned short size=20;
  char buf[20];
  char *msg;
  int val;
  int *ref;

  addr = 0x00c00000;
  while (1) {
    serial_print(0, "\nBexkat1 [");
    serial_printhex(0, addr);
    serial_print(0, "] > ");
    msg = buf;
    serial_getline(0, msg, &size);
    switch (msg[0]) {
    case '?':
      serial_print(0, helpmsg);
      break;
    case 'a':
      msg++;
      while (*msg != '\0') {
	addr = (addr << 4) + hextoi(*msg);
	msg++;
      }
      break;
    case 'v':
      serial_print(0, "\nVGA test starting...\n");
      vga_test();
      break;
    case 's':
      serial_print(0, "\nstart srec upload...\n");
      serial_srec(0);
      break;
    case 'r':
      serial_dumpmem(0, addr, 32);
      break;
    case 'w':
      msg++;
      while (*msg != '\0') {
	val = (val << 4) + hextoi(*msg);
	msg++;
      }
      ref = (int *)addr;
      *ref = val;
      serial_print(0, "\n");
      break;
    default:
      serial_print(0, "\nunknown commmand: ");
      serial_print(0, msg);
      serial_print(0, buf);
    }
  }
}
