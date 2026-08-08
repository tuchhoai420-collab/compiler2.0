# GEMINI.md - Contexto de Desarrollo para EALN-64 Compiler

Este archivo define los mandatos fundacionales, la arquitectura del sistema, la especificación de registros, la estructura del pipeline de compilación y los estándares del proyecto para el compilador **EALN-64 (Estructura de Arreglos Lenguaje Nativo ARM64)**. Cualquier agente o desarrollador que trabaje en esta base de código debe respetar estrictamente estas directrices.

---

## 1. Visión General del Proyecto

**EALN-64** es un compilador nativo ligero de alto rendimiento que opera sin librerías estándar (zero-libc) en sistemas ARM64 Linux. Genera ejecutables binarios en formato ELF directos (`salida.out`) aplicando principios de diseño orientado a datos (DoD) y optimizaciones de bajo nivel para arquitectura ARM64.

### Pilares Arquitectónicos

1. **Diseño Orientado a Datos (DoD):** Representación del AST y tokens mediante **Estructura de Arreglos (SoA - Structure of Arrays)** en lugar de Arreglos de Estructuras (AoS). Esto evita saltos aleatorios de punteros, maximiza el aprovechamiento de la caché de la CPU y permite optimizaciones implícitas para operaciones vectoriales SIMD/NEON.
2. **Memoria Zero-Pause (Sin GC):** Asignación secuencial de bloques masivos en un Arena de 1GB reservado inicialmente mediante la syscall `mmap`. La liberación de memoria es de complejidad $O(1)$ reiniciando el registro de offset a 0, eliminando por completo las pausas de recolectores de basura.
3. **Runtime Bare-Metal (Zero-libc):** El compilador está diseñado de forma autónoma. No tiene dependencia con glibc ni con runtime de C. Todas las operaciones de E/S, llamadas a sistema y control se realizan mediante syscalls directas de Linux para ARM64 (`svc #0`).
4. **Emisión de Código Dinámica:** Genera opcodes de máquina AArch64 en caliente en un búfer interno y los inyecta directamente en un binario ELF autocontenido.

---

## 2. Mapa de Registros Propietario (AArch64)

Para garantizar la consistencia en todos los archivos ensambladores de la base de código, se debe respetar el siguiente mapa de registros:

*   **`x0 - x3`**: Punteros de Contexto (Arenas de memoria y asignación rápida).
*   **`x4 - x7`**: Argumentos Escalares en llamadas de funciones internas.
*   **`x8`**: Registro exclusivo para números de llamadas a sistema (Linux Kernel Syscalls).
*   **`x19 - x28`**: Registros callee-saved. Obligatorio preservar con `stp/ldp` si se usan (`x25`/`x26` = argc/argv salvados en `_start`; `x19`/`x20` = I/O; `x7`/`w9`... según módulo). Nunca asumir que `init_arena` o `map_file_zero_copy` preservan `x0-x18`.
*   **`v0 - v15`**: Acumuladores e instrucciones vectoriales SIMD (NEON).
*   **`sp`**: Stack. Layout del kernel en `_start`: `[sp]=argc`, `[sp+8]=argv[0]`, `[sp+16]=argv[1]`. Se debe leer argc/argv de `sp` (no de registros) pues no se enlaza CRT0.
*   **`x30` (lr)**: Link register. Preservar en `stp/ldp` si la función invoca a otras.

---

## 3. Pipeline de Compilación e Infraestructura

El pipeline del compilador está compuesto por los siguientes módulos integrados:

### A. Inicialización y Bootloader (`src/boot/init.s`)
*   Define el punto de entrada real del ejecutable (`_start`).
*   Captura `argc`/`argv` desde la pila (`sp`) antes de inicializar la arena (el runtime es `ld` puro; el kernel los coloca allí, no en registros).
*   Inicializa la arena de memoria de 1GB (`init_arena`).
*   Resuelve el path del archivo fuente: usa `argv[1]` si se pasa, con fallback a `tests/prueba.esp`.
*   Realiza un mapeo de memoria Zero-Copy del fuente (`map_file_zero_copy`).
*   Ejecuta secuencialmente el Lexer (`iniciar_lexer`) y el Parser (`iniciar_parser`).
*   Inicia el generador ELF (`emitir_elf`) y finaliza con `exit(0)`.

### B. Gestor de Memoria Arena (`src/core/arena_allocator.s`)
*   Mapea 1GB de memoria virtual usando la syscall `mmap` (`#222`) con flags `MAP_PRIVATE | MAP_ANONYMOUS`.
*   Funciones exportadas:
    *   `init_arena`: Reserva la memoria virtual.
    *   `alloc_arena`: Entrega memoria alineada a 16-bytes incrementando un offset interno.
    *   `reset_arena`: Resetea el offset a 0 en $O(1)$.

### C. I/O Zero-Copy (`src/core/io_zero_copy.s`)
*   Abre el archivo fuente y mapea su contenido directamente en memoria virtual mediante `openat` (`#56`) y `mmap` (`#222`). Esto evita el overhead de copiar búferes entre espacio de kernel y usuario.

### D. Analizador Léxico / Lexer (`src/frontend/lexer_core.s`)
*   Tokeniza el archivo fuente rellenando tres arreglos independientes alineados de forma contigua en memoria (SoA):
    *   `token_tipos`: Tipo de token en 1 byte.
    *   `token_inicios`: Puntero directo al inicio del token en la memoria mapeada (8 bytes).
    *   `token_longitudes`: Longitud de cada token en 2 bytes.
    *   `token_conteo`: Número total de tokens detectados.

### E. Analizador Sintáctico / Parser (`src/frontend/parser_core.s`)
*   Recorre secuencialmente el SoA de tokens.
*   Construye un AST compacto en el Arena sin overhead de punteros innecesarios. El AST resultante apunta al primer valor numérico mediante el nodo raíz `ast_root_ptr`.
*   **Tabla de símbolos:** registra cada plano con nombre (`name → nodo AST`) para que las expresiones las referencien por nombre (no por posición).
*   Soporta **tres formas de declaración**:
    *   Escalar: `(sea|fijo) ID = NUM ;` → nodo `AST_VAR_DECL` (100).
    *   Plano: `(sea|fijo) ID = [NUM, ...];` → nodo `AST_VECTOR` (101).
    *   Expresión element-wise: `(sea|fijo) ID = ID ( + | - | * ) ID ;` → nodo `AST_VECBIN` (102).
*   El nodo raíz del AST se expone mediante `ast_root_ptr`.

### F. Generador ELF / Backend (`src/backend/elf_emitter.s`)
*   Convierte los valores literales del AST de ASCII a enteros mediante `parsear_entero`.
*   **Escalares:** emite `MOVZ` directo (carga inmediata).
*   **Planos vectoriales (paradigma alien):** emite código NEON nativo que carga cada literal en un lane de `v0.4S`/`v1.4S` y reduce con **`ADDV` en UNA sola instrucción** (data-parallel), materializando el resultado con `FMOV w0, s0`.
*   **Expresiones element-wise (Hito 3):** el parser resuelve referencias nominales (`a`, `b`) mediante una **tabla de símbolos** en el Arena; el backend carga ambos planos en `v0`/`v1` y aplica la operación SIMD nativa (`ADD`/`SUB`/`MUL v1.4S, ...`) **sin bucles**, reduciendo e imprimiendo el resultado.
*   **Output a STDOUT (zero-libc):** tras la reducción, inyecta una rutina nativa de impresión decimal (`print_dec_bytes`) que convierte el resultado y lo escribe vía syscall `write` directa. El programa generado **imprime el resultado como texto** y sale con código 0.
*   Genera opcodes ARM64 de forma directa en `opcode_buffer`, incluyendo instrucciones de carga inmediata (`MOVZ`), de duplicación SIMD (`DUP v0.4S, w0`), sumas paralelas vectoriales (`ADD v0.4S, v0.4S, v0.4S`), y código de salida (`MOV x8, #93; SVC #0`).
*   Construye y emite un archivo ELF ejecutable autocontenido de aproximadamente 140 bytes en `"salida.out"` mediante llamadas a sistema directas (`openat`, `write`, `close`).

---

## 4. Instrucciones de Compilación, Ejecución y Verificación

### Compilación del Compilador
Para compilar la base de código utilizando la suite GNU Toolchain (`as`, `ld`) sin dependencias de libc:
```bash
make clean && make
```

*Nota: La totalidad del compilador está escrita en Assembly ARM64 puro. No existe código C: el punto de entrada real es `_start` (en `src/boot/init.s`), garantizando la independencia total de dependencias externas y la fidelidad al paradigma nativo.*

### Ejecución del Compilador
El compilador lee el archivo de entrada configurado de forma estática en `tests/prueba.esp` y emite el archivo ELF ejecutable final:
```bash
./ealn-compiler
```

### Verificación de salida.out
Para validar el tamaño y la integridad del binario de salida generado:
```bash
file salida.out
```

Para desensamblar y validar los opcodes ARM64 generados dinámicamente:
```bash
objdump -D -b binary -m aarch64 salida.out
```

---

## 5. Convenciones de Desarrollo y Código

Cualquier adición o modificación a este proyecto debe regirse bajo estas estrictas normas:

1.  **Cero Dependencias Glibc (Zero-libc):** No importar `<stdio.h>`, `<stdlib.h>`, ni ninguna librería estándar de C. Cualquier operación requerida (impresión, E/S, etc.) debe ser programada en Assembly ARM64 puro utilizando syscalls directas de Linux (`svc #0`).
2.  **Assembly Puro / Zero C:** Toda la implementación se escribe exclusivamente en Assembly ARM64 nativo. No se importan librerías de C ni se compila código C. El orquestador real es el punto de entrada `_start` definido en `src/boot/init.s`, que encadena el pipeline completo del compilador.
3.  **Preservación de Registros de la ABI:** Las funciones internas que utilicen registros "callee-saved" (como `x19 - x28`) deben guardar y restaurar dichos registros de forma adecuada en la pila (`sp`) utilizando instrucciones `stp` y `ldp`.
4.  **Alineación a 16 Bytes:** Toda manipulación de la pila (`sp`) y solicitudes en la arena de memoria a través de `alloc_arena` debe conservar una alineación de 16-bytes obligatoria en arquitectura ARM64.
5.  **Simplicidad Extrema (No Over-engineering):** Mantener el pipeline del compilador predecible y optimizado. Evitar capas de abstracción innecesarias que comprometan el rendimiento data-oriented y la filosofía zero-libc del sistema.
