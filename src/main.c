// EALN-64 Compiler - Main Orchestrator
// Filosofía: zero-libc, syscalls directas ARM64, sin overhead de runtime
// Sigue la arquitectura Data-Oriented del proyecto

// Syscall write directa (sin libc)
static long sys_write(int fd, const void *buf, unsigned long len) {
    long ret;
    __asm__ volatile (
        "mov x8, #64\n"   // syscall write
        "svc #0\n"
        : "=r"(ret)
        : "0"(ret),
          "r"((long)fd),
          "r"((long)buf),
          "r"(len)
        : "x8", "memory"
    );
    return ret;
}

// Prototipos de los módulos en asm
extern void iniciar_lexer(void);
extern void iniciar_parser(void);
extern void emitir_elf(void);

static void print(const char *s) {
    const char *p = s;
    while (*p) p++;
    sys_write(1, s, (unsigned long)(p - s));
}

int main(void) {
    print("EALN-64: iniciando compilacion...\n");

    // Pipeline del compilador
    iniciar_lexer();
    iniciar_parser();
    emitir_elf();

    print("EALN-64: compilacion finalizada -> salida.out\n");
    return 0;
}
