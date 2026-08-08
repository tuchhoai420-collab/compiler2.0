# Especificación de Arquitectura de Lenguaje Nativo ARM64 (EALN-64)

## 1. Filosofía Data-Oriented
Estructuras SoA (Estructura de Arreglos). Optimización implícita para SIMD/NEON.

## 2. Mapa de Registros Propietario
* `x0 - x3`: Punteros de Contexto (Arenas).
* `x4 - x7`: Argumentos Escalares.
* `x8`: Syscalls exclusivas (Kernel de Linux).
* `x28`: Puntero de Estado del Agente (Inercia global en caché).
* `v0 - v15`: Acumuladores SIMD obligatorios.

## 3. Memoria Zero-Pause
Asignación por bloques masivos (Arenas) vía `sys_mmap`. Sin Garbage Collector. Liberación en O(1) modificando un solo registro.

## 4. Paradigma Vector-Nativo (datos como PLANO)
El lenguaje declara **planos de datos** (`sea datos = [3, 5, 2, 8];`) y el compilador los transforma
en bloque sobre el hardware NEON: cada literal ocupa un lane de `v0.4S` y las reducciones
(como la suma `ADDV v0.4S`) se ejecutan en **una sola instrucción**, rompiendo el procesamiento
lineal elemento-por-elemento de los lenguajes humanos.

## 5. Hoja de Ruta
1. Vector-native + reducción SIMD (✔): `[3,5,2,8]` → suma = 18.
2. **Output a STDOUT zero-libc (✔):** el programa generado imprime el resultado como texto decimal vía syscall `write`.
3. Expresiones sobre planos (element-wise `+,-,*,/`).
4. Reducciones/filtros nativos (`suma`, acumulados).
5. Shape-types: `(ancho, lanes)` como sistema de tipos.
6. Planos multidimensionales (tensor-planes).
