AS  = as
LD  = ld

ASM_SOURCES = src/boot/init.s \
              src/core/arena_allocator.s \
              src/core/io_zero_copy.s \
              src/frontend/lexer_core.s \
              src/frontend/parser_core.s \
              src/backend/elf_emitter.s

ASM_OBJECTS = $(ASM_SOURCES:.s=.o)
EXECUTABLE  = ealn-compiler

all: $(EXECUTABLE)

$(EXECUTABLE): $(ASM_OBJECTS)
	$(LD) $(ASM_OBJECTS) -o $@

%.o: %.s
	$(AS) -g $< -o $@

clean:
	rm -f $(ASM_OBJECTS) $(EXECUTABLE) salida.out
