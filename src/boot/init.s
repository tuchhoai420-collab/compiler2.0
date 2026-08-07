.global _start

.section .data
    archivo: .string "tests/prueba.esp"

.section .text
_start:
    // 1. Inicializar Arena de memoria masiva
    bl      init_arena
    
    // 2. Mapear archivo fuente por Zero-Copy
    ldr     x1, =archivo
    bl      map_file_zero_copy
    
    // 3. Ejecutar Lexer y Parser para esculpir el AST en la Arena
    bl      iniciar_lexer
    bl      iniciar_parser
    
    // 4. Invocar al Sintetizador Dinámico ELF
    bl      emitir_elf
    
    // 5. Salida limpia del compilador
    mov     x0, #0
    mov     x8, #93
    svc     #0
