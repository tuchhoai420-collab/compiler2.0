.global alloc_arena
.global reset_arena
.global init_arena

.equ ARENA_SIZE, 0x40000000   // 1GB: Zero-Pause masivo original

.section .bss
    arena_base:   .skip 8
    arena_offset: .skip 8

.section .text
init_arena:
    mov     x0, #0
    ldr     x1, =ARENA_SIZE
    mov     x2, #3          // PROT_READ|PROT_WRITE
    mov     x3, #0x22       // MAP_PRIVATE|MAP_ANONYMOUS
    mov     x4, #-1         // fd = -1
    mov     x5, #0          // offset = 0
    mov     x8, #222        // syscall mmap
    svc     #0
    // Verificar error: mmap retorna -errno si falla
    cmn     x0, #4096       // si x0 >= -4096 → error
    b.hi    arena_fallo
    ldr     x1, =arena_base
    str     x0, [x1]
    ldr     x1, =arena_offset
    str     xzr, [x1]
    ret
arena_fallo:
    mov     x0, #2          // exit code 2 = fallo de arena
    mov     x8, #93
    svc     #0

alloc_arena:
    ldr     x1, =arena_base
    ldr     x1, [x1]
    ldr     x2, =arena_offset
    ldr     x3, [x2]
    add     x4, x1, x3
    add     x0, x0, #15
    and     x0, x0, #-16
    add     x3, x3, x0
    str     x3, [x2]
    mov     x0, x4
    ret

reset_arena:
    ldr     x1, =arena_offset
    str     xzr, [x1]
    ret
