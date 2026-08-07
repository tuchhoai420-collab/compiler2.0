.global emitir_elf

.equ AT_FDCWD, -100

.section .bss
    .align 4
    opcode_buffer: .skip 4096

.section .data
    .align 4
    archivo_salida: .string "salida.out"

    elf_header:
        .byte 0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00
        .skip 8
        .short 2
        .short 183
        .word 1
        .quad 0x400078
        .quad 64
        .quad 0
        .word 0
        .short 64
        .short 56
        .short 1
        .short 0, 0, 0

    program_header:
        .word 1
        .word 5
        .quad 0
        .quad 0x400000
        .quad 0x400000
        .quad 0
        .quad 0
        .quad 0x10000

.section .text

// ─────────────────────────────────────────────────────────────────
// parsear_entero: convierte string ASCII a entero
//   entrada: x0 = puntero a string
//   salida:  w0 = valor entero (ESTÁNDAR ARM64 ABI)
// ─────────────────────────────────────────────────────────────────
parsear_entero:
    mov     w0, #0              // resultado en w0 (ABI correcto)
    mov     w2, #10
1:
    ldrb    w3, [x1], #1        // x1 = puntero de lectura
    cmp     w3, #'0'
    b.lt    2f
    cmp     w3, #'9'
    b.gt    2f
    sub     w3, w3, #'0'
    mul     w0, w0, w2
    add     w0, w0, w3
    b       1b
2:
    ret

// ─────────────────────────────────────────────────────────────────
// emitir_elf: genera el ELF de salida a partir del AST
//   sin argumentos, lee ast_root_ptr global
// ─────────────────────────────────────────────────────────────────
emitir_elf:
    // Prólogo: guardar registros callee-saved + lr
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]     // x30 = lr

    ldr     x19, =opcode_buffer
    mov     x20, x19                // x20 = puntero de escritura en buffer

    // ── Verificar AST y generar opcode ──────────────────────────
    ldr     x1, =ast_root_ptr
    ldr     x2, [x1]
    cbz     x2, fallback_opcodes

    ldr     x3, [x2]
    cmp     x3, #100
    b.ne    fallback_opcodes

    ldr     x1, [x2, #16]           // x1 = puntero al valor string del AST
    cbz     x1, fallback_opcodes

    bl      parsear_entero          // resultado en w0 (ABI correcto)

    // Construir instrucción MOV inmediata ARM64: MOVZ x0, #valor
    mov     w4, #0x8000             // plantilla MOVZ x0
    movk    w4, #0xD280, lsl #16
    lsl     w0, w0, #5              // bits [20:5] = inmediato
    orr     w4, w4, w0
    str     w4, [x20], #4
    b       escribir_epilogo

fallback_opcodes:
    // MOV x0, #100 (fallback: MOVZ x0, #100)
    mov     w4, #0x8C80
    movk    w4, #0xD280, lsl #16
    str     w4, [x20], #4

escribir_epilogo:
    // MOV x8, #93  (syscall exit)
    mov     w4, #0xBA8
    movk    w4, #0xD280, lsl #16
    str     w4, [x20], #4
    // SVC #0
    mov     w4, #0x0001
    movk    w4, #0xD400, lsl #16
    str     w4, [x20], #4

    // ── Actualizar tamaños en program_header ────────────────────
    sub     x21, x20, x19           // x21 = bytes de código generado
    mov     x5, #120
    add     x5, x5, x21

    ldr     x6, =program_header
    str     x5, [x6, #32]
    str     x5, [x6, #40]

    // ── Crear archivo de salida ─────────────────────────────────
    // openat(AT_FDCWD, "salida.out", O_WRONLY|O_CREAT|O_TRUNC, 0755)
    mov     x0, AT_FDCWD
    ldr     x1, =archivo_salida
    mov     x2, #577                // O_WRONLY|O_CREAT|O_TRUNC
    mov     x3, #493                // 0755
    mov     x8, #56
    svc     #0
    mov     x22, x0                 // x22 = fd

    // write ELF header (64 bytes)
    mov     x0, x22
    ldr     x1, =elf_header
    mov     x2, #64
    mov     x8, #64
    svc     #0

    // write program header (56 bytes)
    mov     x0, x22
    ldr     x1, =program_header
    mov     x2, #56
    mov     x8, #64
    svc     #0

    // write opcodes
    mov     x0, x22
    mov     x1, x19
    mov     x2, x21
    mov     x8, #64
    svc     #0

    // close
    mov     x0, x22
    mov     x8, #57
    svc     #0

    // Epílogo: restaurar registros
    ldp     x23, x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #48
    ret
