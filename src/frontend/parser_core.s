.global iniciar_parser
.global ast_root_ptr

.equ AST_VAR_DECL,  100

.section .bss
    ast_root_ptr: .skip 8

.section .data
    mock_valor: .string "100"

.section .text
iniciar_parser:
    // Preservar lr: iniciar_parser es una función que llama a alloc_arena
    // sin esto, bl alloc_arena sobrescribe lr y el ret vuelve al lugar incorrecto
    stp     x19, x30, [sp, #-16]!   // guardar x19 y lr (x30) en stack

    // Solicitar memoria en la Arena Cero-Pausa
    mov     x0, #32
    bl      alloc_arena
    
    // Anclar la raíz del AST
    ldr     x1, =ast_root_ptr
    str     x0, [x1]
    mov     x19, x0                 // preservar puntero al nodo AST

    // Construir nodo de declaración
    mov     x2, AST_VAR_DECL
    str     x2, [x19]

    // Asignar carga útil
    ldr     x3, =mock_valor
    str     x3, [x19, #16]

    // Restaurar y retornar limpio
    ldp     x19, x30, [sp], #16    // restaurar x19 y lr
    ret
