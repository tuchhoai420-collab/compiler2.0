.global iniciar_parser
.global ast_root_ptr

.equ AST_VAR_DECL,  100
.equ AST_VECTOR,    101
.equ TOK_ID,        1
.equ TOK_NUM,       2
.equ TOK_IGUAL,     3
.equ TOK_PUNTOCOMA, 4
.equ TOK_SEA,       5
.equ TOK_FIJO,      6
.equ TOK_LBRACKET,  11
.equ TOK_RBRACKET,  12
.equ TOK_COMMA,     13

.section .bss
    ast_root_ptr: .skip 8

.section .text
// ─────────────────────────────────────────────────────────────────
// Inicia el Parser (Visión Alienígena: lee tokens SoA secuencialmente)
// ─────────────────────────────────────────────────────────────────
iniciar_parser:
    stp     x19, x20, [sp, #-48]!
    stp     x21, x22, [sp, #16]
    stp     x23, x30, [sp, #32]

    ldr     x20, =token_conteo
    ldr     x20, [x20]
    mov     x21, #0                 // Índice de token actual
    ldr     x22, =token_tipos
    ldr     x23, =token_inicios

parser_loop:
    cmp     x21, x20
    b.ge    parser_fin

    ldrb    w0, [x22, x21]
    
    // Buscar inicio de declaración: sea o fijo
    cmp     w0, TOK_SEA
    b.eq    parse_declaracion
    cmp     w0, TOK_FIJO
    b.eq    parse_declaracion

    add     x21, x21, #1
    b       parser_loop

parse_declaracion:
    // x21 apunta a SEA/FIJO. Esperamos: ID, IGUAL, luego NUM (escalar) o [nums] (vector)
    // 1. Bounds mínimos
    add     x1, x21, #4
    cmp     x1, x20
    b.ge    parser_error

    // 2. ID
    add     x1, x21, #1
    ldrb    w1, [x22, x1]
    cmp     w1, TOK_ID
    b.ne    parser_error

    // 3. IGUAL
    add     x1, x21, #2
    ldrb    w1, [x22, x1]
    cmp     w1, TOK_IGUAL
    b.ne    parser_error

    // 4. Despachar según token +3: LBRACKET (vector) o NUM (escalar)
    add     x1, x21, #3
    ldrb    w1, [x22, x1]
    cmp     w1, TOK_LBRACKET
    b.eq    parse_vector
    cmp     w1, TOK_NUM
    b.ne    parser_error

    // 5. Escalar: NUM + PUNTOCOMA
    add     x1, x21, #4
    ldrb    w1, [x22, x1]
    cmp     w1, TOK_PUNTOCOMA
    b.ne    parser_error

    // Gramática escalar válida. Crear nodo AST.
    mov     x0, #32                 // Tamaño nodo AST (incluye campo 'next' en offset 24)
    bl      alloc_arena
    
    // Si es la primera declaración, es la raíz. Si no, encadenar.
    ldr     x1, =ast_root_ptr
    ldr     x2, [x1]
    cbnz    x2, encadenar_nodo
    str     x0, [x1]
    b       nodo_config

encadenar_nodo:
    // Buscar el último nodo actual (recorrido simple)
    mov     x3, x2
1:
    ldr     x4, [x3, #24]           // Cargar 'next'
    cbz     x4, 2f
    mov     x3, x4
    b       1b
2:
    str     x0, [x3, #24]           // El último nodo ahora apunta al nuevo

nodo_config:
    mov     x19, x0                 // puntero al nuevo nodo
    str     xzr, [x19, #24]         // nuevo->next = NULL
    mov     w2, AST_VAR_DECL
    str     w2, [x19]               // Tipo de nodo

    // Guardar puntero al nombre (ID)
    add     x1, x21, #1
    ldr     x2, [x23, x1, lsl #3]
    str     x2, [x19, #8]

    // Guardar puntero al valor (NUM)
    add     x1, x21, #3
    ldr     x2, [x23, x1, lsl #3]
    str     x2, [x19, #16]

    // Avanzar índice de tokens consumidos
    add     x21, x21, #5
    b       parser_loop

// ─────────────────────────────────────────────────────────────
// parse_vector: sea/fijo ID = [NUM, NUM, ...];
//   nodo: [type:4][name:8][count:4][pad:4][next:8][elems:count*8]
//   type = AST_VECTOR (101), 'elems' apunta a cada literal
// ─────────────────────────────────────────────────────────────
parse_vector:
    // x21 en SEA/FIJO. Tokens: +1 ID, +2 '=', +3 '[', elems, ']', ';'
    mov     x6, #0                  // contador de elementos
    add     x7, x21, #4             // cursor sobre el primer NUM
pvector_count:
    cmp     x7, x20
    b.ge    parser_error
    ldrb    w0, [x22, x7]
    cmp     w0, TOK_NUM
    b.ne    parser_error
    add     x6, x6, #1
    add     x7, x7, #1
    cmp     x7, x20
    b.ge    parser_error
    ldrb    w0, [x22, x7]
    cmp     w0, TOK_COMMA
    b.eq    3f
    cmp     w0, TOK_RBRACKET
    b.eq    4f
    b       parser_error
3:
    add     x7, x7, #1
    b       pvector_count
4:
    // x7 en ']'. Verificar que siga ';'
    add     x1, x7, #1
    cmp     x1, x20
    b.ge    parser_error
    ldrb    w0, [x22, x1]
    cmp     w0, TOK_PUNTOCOMA
    b.ne    parser_error

    // Asignar nodo: 32 + 8*count
    mov     x0, #32
    mov     x2, x6
    lsl     x2, x2, #3
    add     x0, x0, x2
    bl      alloc_arena

    // Encadenar nodo
    ldr     x1, =ast_root_ptr
    ldr     x2, [x1]
    cbnz    x2, pvector_encadenar
    str     x0, [x1]
    b       pvector_config
pvector_encadenar:
    mov     x3, x2
5:
    ldr     x4, [x3, #24]
    cbz     x4, 6f
    mov     x3, x4
    b       5b
6:
    str     x0, [x3, #24]
pvector_config:
    mov     x19, x0
    str     xzr, [x19, #24]         // next = NULL
    mov     w2, AST_VECTOR
    str     w2, [x19]               // type
    str     w6, [x19, #16]          // count
    add     x1, x21, #1
    ldr     x2, [x23, x1, lsl #3]   // nombre
    str     x2, [x19, #8]
    // rellenar punteros a elementos en [x19 + 32 ..]
    add     x4, x19, #32
    mov     x5, x21
    add     x5, x5, #4              // primer elemento (token +4)
    mov     x7, x6                  // iteraciones = count
pvector_fill:
    cbz     x7, pvector_fin
    ldr     x1, [x23, x5, lsl #3]
    str     x1, [x4], #8
    add     x5, x5, #2
    sub     x7, x7, #1
    b       pvector_fill
pvector_fin:
    // avanzar x21: 2*count + 5 tokens consumidos
    mov     x0, x6
    lsl     x0, x0, #1
    add     x0, x0, #5
    add     x21, x21, x0
    b       parser_loop

parser_error:
    // En caso de error sintáctico, simplemente avanzamos (por ahora)
    add     x21, x21, #1
    b       parser_loop

parser_fin:
    ldp     x23, x30, [sp, #32]
    ldp     x21, x22, [sp, #16]
    ldp     x19, x20, [sp], #48
    ret

