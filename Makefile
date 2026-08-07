AS  = as
CC  = gcc
LD  = ld

ASM_SOURCES = src/boot/init.s \
              src/core/arena_allocator.s \
              src/core/io_zero_copy.s \
              src/frontend/lexer_core.s \
              src/frontend/parser_core.s \
              src/backend/elf_emitter.s

C_SOURCES   = src/main.c

ASM_OBJECTS = $(ASM_SOURCES:.s=.o)
C_OBJECTS   = $(C_SOURCES:.c=.o)
OBJECTS     = $(ASM_OBJECTS) $(C_OBJECTS)
EXECUTABLE  = ealn-compiler

all: $(EXECUTABLE)

$(EXECUTABLE): $(OBJECTS)
	$(LD) $(OBJECTS) -o $@

%.o: %.s
	$(AS) -g $< -o $@

%.o: %.c
	$(CC) -c -ffreestanding -nostdlib -o $@ $<

clean:
	rm -f $(OBJECTS) $(EXECUTABLE) salida.out
