.global _start

.section .data
    default_file: .string "tests/prueba.esp"

.section .text
_start:
    // Capturar argc/argv de la pila del kernel (ld sin crt0).
    // Linux ARM64 coloca en SP: [sp]=argc, [sp+8]=argv[0], [sp+16]=argv[1].
    // Se salvan en callee-saved (x25/x26) antes de cualquier clobber.
    mov     x25, sp              // x25 = base de pila (argc/argv/envp)
    ldr     x26, [x25]          // x26 = argc (leído de [sp])

    // 1. Inicializar Arena de memoria masiva
    bl      init_arena
    
            // 2. Resolver path de fuente: argv[1] si existe, sino default.
    //    x26 = argc; x25 = base de pila. argv[0]=[x25+8], argv[1]=[x25+16].
    mov     x0, x26              // x0 = argc
    cmp     x0, #2               // argc >= 2 ?
    blt     use_default          // no: usar default
    ldr     x1, [x25, #16]       // x1 = argv[1]  (argv[0] está en [x25+8])
    cbz     x1, use_default      // NULL args: usar default
    b       map_source
use_default:
    ldr     x1, =default_file    // x1 = &"tests/prueba.esp"
map_source:
    // 2b. Mapear archivo fuente por Zero-Copy (recibe path en x1)
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
