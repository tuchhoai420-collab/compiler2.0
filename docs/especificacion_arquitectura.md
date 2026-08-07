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
