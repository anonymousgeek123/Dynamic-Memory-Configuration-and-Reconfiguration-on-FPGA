# Dynamic-Memory-Configuration-and-Reconfiguration-on-FPGA

In modern SoC (System on Chip) designs, multiple hardware components such as CPU, GPU, 
SYS and DMA engines share a common DDR memory pool. Without a proper memory 
management system, one component can exhaust all available memory pages, causing other 
components to stall or fail. This project implements a fully hardware-based dynamic DDR 
memory allocator in SystemVerilog. The allocator divides DDR memory into independent 
regions — one per hardware component — each backed by a circular FIFO of free page 
addresses. A reconfiguration FSM continuously monitors region utilization and autonomously 
transfers pages between regions to prevent starvation, with zero software involvement. 

2. SYSTEM OVERVIEW 
 • DDR Memory Model — simulated address space divided into N regions 
 • Region Manager — tracks which region owns which address blocks 
 • Per-Region FIFO — circular queue of free DDR addresses per region (CPU, GPU, DMA, 
  etc.) 
 • Allocator — pops from a region's FIFO on allocation request 
 • Reclaimer — pushes freed addresses back to the tail 
 • Dynamic Reconfiguration — resizes FIFO capacity between regions at runtime 
 • Testbench — drives all scenarios including overflow, reconfig, and starvation
