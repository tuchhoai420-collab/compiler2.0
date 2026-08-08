.global emitir_elf

.equ AT_FDCWD, -100
.equ AST_VECTOR, 101
.equ AST_VECBIN, 102
.equ AST_VECBIN_BAD, 103

// Códigos de operación (coinciden con OP_* del parser)
.equ OP_ADD, 0
.equ OP_SUB, 1
.equ OP_MUL, 2

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

    // Rutina nativa de impresión decimal signed (output a STDOUT, zero-libc).
    // Entrada: w0 = int32 signed. Detecta signo, imprime '-' si negativo.
    // Diseño inline puro (sin frame C). Cae al epílogo.
    .align 4
    print_dec_bytes:
        .word 0xd100c3ff, 0xd2800009, 0x910073e2, 0x52800143
        .word 0x5280000a, 0x37f80140, 0x1ac30804, 0x1b038085
        .word 0x2a0403e0, 0x1100c0a5, 0xd1000442, 0x39000045
        .word 0x91000529, 0x35ffff20, 0x14000004, 0x5280002a
        .word 0x4b0003e0, 0x17fffff5, 0x360000aa, 0xd1000442
        .word 0x528005a5, 0x39000045, 0x91000529, 0xd2800020
        .word 0xaa0203e1, 0xaa0903e2, 0xd2800808, 0xd4000001
        .word 0x9100c3ff

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
    mov     w23, #0                 // flag: ¿vimos un nodo vector?

    // ── Bucle de Emisión Iterativo (Visión Alienígena) ──────────
    ldr     x1, =ast_root_ptr
    ldr     x21, [x1]               // x21 = puntero al nodo actual
    cbz     x21, fallback_opcodes

emision_loop:
    cbz     x21, emision_finalizada

    ldr     w3, [x21]               // Tipo de nodo
    cmp     w3, #102                // AST_VECBIN
    b.eq    emit_bin
    cmp     w3, #101                // AST_VECTOR
    b.eq    emit_vector
    cmp     w3, #100                // AST_VAR_DECL
    b.ne    siguiente_nodo

    ldr     x1, [x21, #16]          // x1 = puntero al valor string
    cbz     x1, siguiente_nodo

    // Preservar puntero de escritura y nodo actual antes del bl
    stp     x20, x21, [sp, #-16]!
    bl      parsear_entero          // resultado en w0
    ldp     x20, x21, [sp], #16

    // Generar: MOVZ w0, #valor
    mov     w4, #0
    movk    w4, #0x5280, lsl #16
    lsl     w0, w0, #5
    orr     w4, w4, w0
    str     w4, [x20], #4
    b       siguiente_nodo

// ─────────────────────────────────────────────────────────────
// emit_vector: Visión Alienígena — datos como PLANO.
//   Solo el nodo TERMINAL (último) emite la reducción + impresión.
//   Carga cada literal en un lane de v0.4S y reduce con ADDV.
// ─────────────────────────────────────────────────────────────
emit_vector:
    // ¿es el nodo terminal? si no, es solo una definición de datos
    ldr     x22, [x21, #24]
    cbnz    x22, siguiente_nodo
    ldr     w4, [x21, #16]          // count de elementos
    cmp     w4, #4
    ble     v_cap
    mov     w4, #4                  // tope de 4 lanes (.4S)
v_cap:
    add     x6, x21, #32            // x6 = arreglo de punteros a literales
    mov     w7, #0                  // índice de lane (0..3)

v_lane_loop:
    cbz     w4, v_reduc
    ldr     x1, [x6], #8            // x1 = puntero al literal
    stp     x20, x21, [sp, #-16]!
    bl      parsear_entero          // w0 = valor del elemento
    ldp     x20, x21, [sp], #16

    // emitir: movz w1, #valor  (0x52800001 | (valor << 5))
    //   El literal se hornea como inmediato, independiente del runtime
    movz    w12, #0x0001
    movk    w12, #0x5280, lsl #16
    lsl     w0, w0, #5
    orr     w12, w12, w0
    str     w12, [x20], #4

    // emitir: mov v0.s[n], w1  (0x4e041c20 | (n<<19))
    movz    w13, #0x1c20
    movk    w13, #0x4e04, lsl #16
    mov     w12, w7
    lsl     w12, w12, #19
    orr     w13, w13, w12
    str     w13, [x20], #4

    add     w7, w7, #1
    sub     w4, w4, #1
    b       v_lane_loop

v_reduc:
    // emitir: addv s0, v0.4s  (0x4eb1b800)  → reducción en S0
    movz    w12, #0xb800
    movk    w12, #0x4eb1, lsl #16
    str     w12, [x20], #4
    b       emit_print_tail

// ─────────────────────────────────────────────────────────────
// emit_print_tail: materializa W0 (fmov), copia la rutina de
//   impresión decimal y fuerza salida limpia (mov w0, #0).
// ─────────────────────────────────────────────────────────────
emit_print_tail:
    // fmov w0, s0  (0x1e260000) → materializa W0 (ley del hardware)
    movz    w12, #0x0000
    movk    w12, #0x1e26, lsl #16
    str     w12, [x20], #4
    // copia print_dec_bytes (29 palabras, sin ret)
    ldr     x14, =print_dec_bytes
    mov     w15, #29
print_copy:
    ldr     w12, [x14], #4
    str     w12, [x20], #4
    sub     w15, w15, #1
    cbnz    w15, print_copy
    // mov w0, #0  (0x52800000) → salida limpia tras imprimir
    movz    w12, #0x0000
    movk    w12, #0x5280, lsl #16
    str     w12, [x20], #4
    mov     w23, #1                 // marcamos vector/expr visto
    b       siguiente_nodo

// ─────────────────────────────────────────────────────────────
// emit_bin: expresión element-wise entre dos planos (SIMD NEON).
//   v0 = plano izq, v1 = plano der, v1.4S = v1.4S OP v0.4S,
//   reduce v1 (ADDV) e imprime. Solo emite si es nodo terminal.
// ─────────────────────────────────────────────────────────────
emit_bin:
    // ¿es el nodo terminal? (debe serlo para imprimir el resultado)
    ldr     x22, [x21, #24]
    cbnz    x22, siguiente_nodo
    ldr     x6, [x21, #8]           // nodo plano izquierdo
    ldr     x7, [x21, #16]          // nodo plano derecho

    // ── Shape-check en backend: verificar tipo válido ──
    ldr     w4, [x21, #0]           // tipo de nodo
    cmp     w4, #AST_VECBIN_BAD
    b.eq    bin_shape_fallback       // si es inválido, no emitir NEON

    // ── cargar plano izquierdo en v0.4S ──
    ldr     w4, [x6, #16]           // count izq
    cmp     w4, #4
    ble     b_cap0
    mov     w4, #4
b_cap0:
    add     x8, x6, #32             // arreglo de literales
    mov     w9, #0                  // lane
b_load0:
    cbz     w4, b_done0
    ldr     x1, [x8], #8
    stp     x20, x21, [sp, #-16]!
    bl      parsear_entero          // w0 = valor
    ldp     x20, x21, [sp], #16
    // movz w1, #valor
    movz    w12, #0x0001
    movk    w12, #0x5280, lsl #16
    lsl     w0, w0, #5
    orr     w12, w12, w0
    str     w12, [x20], #4
    // mov v0.s[n], w1  (0x4e041c20 | n<<19)
    movz    w13, #0x1c20
    movk    w13, #0x4e04, lsl #16
    mov     w12, w9
    lsl     w12, w12, #19
    orr     w13, w13, w12
    str     w13, [x20], #4
    add     w9, w9, #1
    sub     w4, w4, #1
    b       b_load0
b_done0:

    // ── cargar plano derecho en v1.4S ──
    ldr     w4, [x7, #16]           // count der
    cmp     w4, #4
    ble     b_cap1
    mov     w4, #4
b_cap1:
    add     x8, x7, #32
    mov     w9, #0
b_load1:
    cbz     w4, b_done1
    ldr     x1, [x8], #8
    stp     x20, x21, [sp, #-16]!
    bl      parsear_entero
    ldp     x20, x21, [sp], #16
    // movz w1, #valor
    movz    w12, #0x0001
    movk    w12, #0x5280, lsl #16
    lsl     w0, w0, #5
    orr     w12, w12, w0
    str     w12, [x20], #4
    // mov v1.s[n], w1  (0x4e041c21 | n<<19)
    movz    w13, #0x1c21
    movk    w13, #0x4e04, lsl #16
    mov     w12, w9
    lsl     w12, w12, #19
    orr     w13, w13, w12
    str     w13, [x20], #4
    add     w9, w9, #1
    sub     w4, w4, #1
    b       b_load1
b_done1:

    // ── emitir operación element-wise: v1.4S = v1.4S OP v0.4S ──
    ldr     w5, [x21, #32]          // código de operación
    cmp     w5, OP_ADD
    b.eq    b_add
    cmp     w5, OP_SUB
    b.eq    b_sub
    cmp     w5, OP_MUL
    b.eq    b_mul
    b       siguiente_nodo          // op desconocida: no emite
b_add:
    // add v1.4s, v1.4s, v0.4s = 0x4ea08421
    movz    w12, #0x8421
    movk    w12, #0x4ea0, lsl #16
    str     w12, [x20], #4
    b       b_reduc
b_sub:
    // sub v1.4s, v0.4s, v1.4s = 0x6ea18401  (a - b, orden correcto)
    movz    w12, #0x8401
    movk    w12, #0x6ea1, lsl #16
    str     w12, [x20], #4
    b       b_reduc
b_mul:
    // mul v1.4s, v1.4s, v0.4s = 0x4ea09c21
    movz    w12, #0x9c21
    movk    w12, #0x4ea0, lsl #16
    str     w12, [x20], #4
b_reduc:
    // addv s0, v1.4s = 0x4eb1b820  → reduce v1 en S0
    movz    w12, #0xb820
    movk    w12, #0x4eb1, lsl #16
    str     w12, [x20], #4
    b       emit_print_tail

bin_shape_fallback:
    // Shape mismatch: no emitir NEON, solo avanzar al siguiente nodo
    b       siguiente_nodo

siguiente_nodo:
    ldr     x21, [x21, #24]         // x21 = nodo->next
    b       emision_loop

emision_finalizada:
    cbnz    x23, escribir_epilogo   // si hubo vector, la reducción ya está
    // -- Visión Alienígena: Demostración SIMD legacy (solo escalares) --
    // DUP v0.4S, w0
    mov     w4, #0x0c00
    movk    w4, #0x4e04, lsl #16
    str     w4, [x20], #4

    // ADD v0.4S, v0.4S, v0.4S
    mov     w4, #0x8400
    movk    w4, #0x4e20, lsl #16
    str     w4, [x20], #4

    b       escribir_epilogo

fallback_opcodes:
    // MOV x0, #100 (fallback: MOVZ x0, #100)
    mov     w4, #0x0C80
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
