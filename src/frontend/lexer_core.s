.global iniciar_lexer
.global token_tipos
.global token_inicios
.global token_longitudes
.global token_conteo

.equ TOK_EOF,       0
.equ TOK_ID,        1
.equ TOK_NUM,       2
.equ TOK_IGUAL,     3
.equ TOK_PUNTOCOMA, 4
.equ TOK_SEA,       5
.equ TOK_FIJO,      6
.equ TOK_MAS,       7
.equ TOK_MENOS,     8
.equ TOK_MAYOR,     9
.equ TOK_MENOR,     10
.equ TOK_LBRACKET,  11
.equ TOK_RBRACKET,  12
.equ TOK_COMMA,     13

.section .bss
    // Estructura de Arreglos (SoA) para Tokens
    .align 4
    token_tipos:      .skip 8192
    token_inicios:    .skip 8192
    token_longitudes: .skip 8192
    token_conteo:     .skip 8

.section .text
// ─────────────────────────────────────────────────────────────────
// Inicia el Análisis Léxico (Visión Alienígena: Cero copias, Data-Oriented)
// ─────────────────────────────────────────────────────────────────
iniciar_lexer:
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    ldr     x19, =fuente_ptr
    ldr     x19, [x19]          // Puntero base del archivo
    ldr     x20, =fuente_size
    ldr     x20, [x20]          // Tamaño del archivo
    add     x20, x19, x20       // Puntero de fin

    mov     x21, #0             // Contador de tokens

    ldr     x23, =token_tipos
    ldr     x24, =token_inicios
    ldr     x25, =token_longitudes

lex_loop:
    cmp     x19, x20
    b.ge    lex_fin

    ldrb    w22, [x19]          // Leer caracter

    // Ignorar espacios en blanco (optimizado, asumiendo solo ' ', '\n', '\r', '\t')
    cmp     w22, #32            // ' '
    b.eq    lex_avanzar
    cmp     w22, #10            // '\n'
    b.eq    lex_avanzar
    cmp     w22, #13            // '\r'
    b.eq    lex_avanzar
    cmp     w22, #9             // '\t'
    b.eq    lex_avanzar

    // Si no es espacio, identificamos.
    // Puntuación:
    cmp     w22, #'='
    b.ne    tok_puntocoma
    mov     w0, TOK_IGUAL
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_puntocoma:
    cmp     w22, #';'
    b.ne    tok_mas
    mov     w0, TOK_PUNTOCOMA
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_mas:
    cmp     w22, #'+'
    b.ne    tok_menos
    mov     w0, TOK_MAS
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_menos:
    cmp     w22, #'-'
    b.ne    tok_mayor
    mov     w0, TOK_MENOS
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_mayor:
    cmp     w22, #'>'
    b.ne    tok_menor
    mov     w0, TOK_MAYOR
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_menor:
    cmp     w22, #'<'
    b.ne    tok_llave
    mov     w0, TOK_MENOR
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_llave:
    cmp     w22, #'['
    b.ne    tok_rbracket
    mov     w0, TOK_LBRACKET
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_rbracket:
    cmp     w22, #']'
    b.ne    tok_comma
    mov     w0, TOK_RBRACKET
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop
tok_comma:
    cmp     w22, #','
    b.ne    check_numeros
    mov     w0, TOK_COMMA
    mov     x1, x19
    mov     w2, #1
    bl      registrar_token
    add     x19, x19, #1
    b       lex_loop

check_numeros:
    // Números
    cmp     w22, #'0'
    b.lt    3f
    cmp     w22, #'9'
    b.gt    3f
    mov     x1, x19
lex_num_loop:
    add     x19, x19, #1
    cmp     x19, x20
    b.ge    lex_num_fin
    ldrb    w22, [x19]
    cmp     w22, #'0'
    b.lt    lex_num_fin
    cmp     w22, #'9'
    b.le    lex_num_loop
lex_num_fin:
    mov     w0, TOK_NUM
    sub     x2, x19, x1
    bl      registrar_token
    b       lex_loop
3:
    // Identificadores/Palabras clave
    mov     x1, x19
lex_id_loop:
    add     x19, x19, #1
    cmp     x19, x20
    b.ge    lex_id_fin
    ldrb    w22, [x19]
    // Rango simple: a-z, A-Z, _
    // Alien perspective: we just read until we hit a delimiter to be fast
    cmp     w22, #32
    b.le    lex_id_fin
    cmp     w22, #'='
    b.eq    lex_id_fin
    cmp     w22, #';'
    b.eq    lex_id_fin
    cmp     w22, #'+'
    b.eq    lex_id_fin
    cmp     w22, #'-'
    b.eq    lex_id_fin
    cmp     w22, #'>'
    b.eq    lex_id_fin
    cmp     w22, #'<'
    b.eq    lex_id_fin
    b       lex_id_loop
lex_id_fin:
    sub     x2, x19, x1         // x2 = longitud
    mov     w0, TOK_ID          // Por defecto ID

    // Chequear "sea" (longitud 3)
    cmp     x2, #3
    b.ne    check_fijo
    ldrb    w3, [x1]
    cmp     w3, #'s'
    b.ne    check_fijo
    ldrb    w3, [x1, #1]
    cmp     w3, #'e'
    b.ne    check_fijo
    ldrb    w3, [x1, #2]
    cmp     w3, #'a'
    b.ne    check_fijo
    mov     w0, TOK_SEA
    b       lex_id_registrar

check_fijo:
    // Chequear "fijo" (longitud 4)
    cmp     x2, #4
    b.ne    lex_id_registrar
    ldr     w3, [x1]            // Leer 4 bytes de golpe
    // "fijo" -> 'f'=66, 'i'=69, 'j'=6a, 'o'=6f
    // Little endian: 6f 6a 69 66
    movz    w4, #0x6966
    movk    w4, #0x6f6a, lsl #16
    cmp     w3, w4
    b.ne    lex_id_registrar
    mov     w0, TOK_FIJO

lex_id_registrar:
    bl      registrar_token
    b       lex_loop

lex_avanzar:
    add     x19, x19, #1
    b       lex_loop

lex_fin:
    // Registrar EOF
    mov     w0, TOK_EOF
    mov     x1, x19
    mov     w2, #0
    bl      registrar_token

    ldr     x0, =token_conteo
    str     x21, [x0]

    ldp     x23, x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #48
    ret

registrar_token:
    // w0 = tipo, x1 = inicio, w2 = longitud
    // Usa x21 como índice, x23/24/25 como bases
    strb    w0, [x23, x21]      // Tipo es 1 byte
    str     x1, [x24, x21, lsl #3] // Puntero es 8 bytes
    strh    w2, [x25, x21, lsl #1] // Longitud es 2 bytes
    add     x21, x21, #1
    ret
