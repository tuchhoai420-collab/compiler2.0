.global map_file_zero_copy
.global fuente_ptr
.global fuente_size

.equ AT_FDCWD,    -100
.equ O_RDONLY,    0
.equ PROT_READ,   1
.equ MAP_PRIVATE, 2

.section .bss
    stat_buffer: .skip 128
    fuente_ptr:  .skip 8
    fuente_size: .skip 8

.section .text
map_file_zero_copy:
    // x1 = puntero al nombre del archivo (recibido del caller)
    // openat(AT_FDCWD, x1, O_RDONLY, 0)
    mov     x0, AT_FDCWD    // x0 = AT_FDCWD (-100)
    // x1 ya contiene el path del archivo — NO sobrescribir
    mov     x2, O_RDONLY    // x2 = flags
    mov     x3, #0          // x3 = mode
    mov     x8, #56         // syscall openat
    svc     #0
    cmp     x0, #0
    b.lt    panico_io
    mov     x19, x0

    mov     x0, x19
    ldr     x1, =stat_buffer
    mov     x8, #80
    svc     #0
    ldr     x1, =stat_buffer
    ldr     x20, [x1, #48]
    ldr     x2, =fuente_size
    str     x20, [x2]

    mov     x0, #0
    mov     x1, x20
    mov     x2, PROT_READ
    mov     x3, MAP_PRIVATE
    mov     x4, x19
    mov     x5, #0
    mov     x8, #222
    svc     #0
    ldr     x1, =fuente_ptr
    str     x0, [x1]

    mov     x0, x19
    mov     x8, #57
    svc     #0
    ret

panico_io:
    mov     x0, #1
    mov     x8, #93
    svc     #0
