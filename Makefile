# EALN-64 Compiler — Pure Assembly ARM64 backend (zero-libc)
# ------------------------------------------------------------------
# Native build (en host arm64):   make
# Cross build (desde x86_64):     make CROSS=aarch64-linux-gnu-
# ------------------------------------------------------------------
CROSS  ?=
AS     := $(CROSS)as
LD     := $(CROSS)ld

ASM_SOURCES = src/boot/init.s \
              src/core/arena_allocator.s \
              src/core/io_zero_copy.s \
              src/frontend/lexer_core.s \
              src/frontend/parser_core.s \
              src/backend/elf_emitter.s

ASM_OBJECTS = $(ASM_SOURCES:.s=.o)
EXECUTABLE  = ealn-compiler

# Para cross-build, el cross-ld (aarch64-linux-gnu-ld) ya produce output
# aarch64 por defecto (tripleta); no necesita -m. La flag native `ld`
# tampoco necesita nada (host = arm64).
LD_FLAGS :=

all: $(EXECUTABLE)

$(EXECUTABLE): $(ASM_OBJECTS)
	$(LD) $(LD_FLAGS) $(ASM_OBJECTS) -o $@

%.o: %.s
	$(AS) -g $< -o $@

clean:
	rm -f $(ASM_OBJECTS) $(EXECUTABLE) salida.out

# Ejecuta todos los tests (native: sobre el host; cross: bajo qemu)
test: $(EXECUTABLE)
	@if command -v qemu-aarch64-static >/dev/null 2>&1 && [ "$(CROSS)" = "aarch64-linux-gnu-" ]; then \
		QEMU=qemu-aarch64-static; \
	else \
		QEMU=; \
	fi; \
	export QEMU; \
	bash tests/run_tests.sh --measure

.PHONY: all clean test
