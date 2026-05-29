MULTIBOOT2_MAGIC equ 0xe85250d6
MULTIBOOT2_ARCH  equ 0

section .multiboot
align 8
global __kernel_start
__kernel_start:
multiboot_header:
    dd MULTIBOOT2_MAGIC
    dd MULTIBOOT2_ARCH
    dd multiboot_end - multiboot_header
    dd -(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCH + (multiboot_end - multiboot_header))
    align 8
    dw 6
    dw 0
    dd 8
    align 8
    dw 0
    dw 0
    dd 8
multiboot_end:

section .boot
bits 32
global _start
extern kernel_main

_start:
    cli
    cld
    mov [multiboot_magic], eax
    mov [multiboot_info], ebx
    mov esp, stack_top
    cmp eax, 0x36d76289
    jne .err
    call setup_paging
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax
    mov eax, pml4
    mov cr3, eax
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    or eax, 1 << 11
    wrmsr
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax
    lgdt [gdt64_ptr]
    jmp 0x08:long_mode_start

.err:
    mov dword [0xb8000], 0x4f524f45
    mov dword [0xb8004], 0x4f524f52
    mov dword [0xb8008], 0x4f214f52
    hlt

setup_paging:
    mov edi, pml4
    xor eax, eax
    mov ecx, (6 * 4096) / 4
    rep stosd
    mov eax, pdpt
    or eax, 0x3
    mov [pml4], eax
    mov eax, pd
    or eax, 0x3
    mov [pdpt], eax
    mov eax, pd
    add eax, 0x1000
    or eax, 0x3
    mov [pdpt + 8], eax
    mov eax, pd
    add eax, 0x2000
    or eax, 0x3
    mov [pdpt + 16], eax
    mov eax, pd
    add eax, 0x3000
    or eax, 0x3
    mov [pdpt + 24], eax
    mov edi, pd
    mov eax, 0x83
    mov ecx, 2048
.fill_pd:
    mov [edi], eax
    add eax, 0x200000
    add edi, 8
    dec ecx
    jnz .fill_pd
    ret

section .text
bits 64
long_mode_start:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov rsp, stack_top
    mov edi, [multiboot_magic]
    mov esi, [multiboot_info]
    call kernel_main
.halt:
    hlt
    jmp .halt

global asm_outb
asm_outb:
    mov dx, di
    mov al, sil
    out dx, al
    ret

global asm_inb
asm_inb:
    mov dx, di
    in al, dx
    movzx eax, al
    ret

global asm_outl
asm_outl:
    mov dx, di
    mov eax, esi
    out dx, eax
    ret

global asm_inl
asm_inl:
    mov dx, di
    in eax, dx
    ret

global asm_outw
asm_outw:
    mov dx, di
    mov ax, si
    out dx, ax
    ret

global asm_inw
asm_inw:
    mov dx, di
    in ax, dx
    movzx eax, ax
    ret

global asm_lgdt
asm_lgdt:
    lgdt [rdi]
    ret

global asm_lidt
asm_lidt:
    lidt [rdi]
    ret

global asm_sti
asm_sti:
    sti
    ret

global asm_cli
asm_cli:
    cli
    ret

global asm_hlt
asm_hlt:
    hlt
    ret

global asm_int32
asm_int32:
    int 0x20
    ret

%macro EXCEPT_NO_ERR 1
global except%1
except%1:
    push 0
    push %1
    jmp except_common
%endmacro

%macro EXCEPT_ERR 1
global except%1
except%1:
    push %1
    jmp except_common
%endmacro

%macro IRQ_STUB 2
global irq%1
irq%1:
    push 0
    push %2
    jmp irq_common
%endmacro

EXCEPT_NO_ERR 0
EXCEPT_NO_ERR 1
EXCEPT_NO_ERR 2
EXCEPT_NO_ERR 3
EXCEPT_NO_ERR 4
EXCEPT_NO_ERR 5
EXCEPT_NO_ERR 6
EXCEPT_NO_ERR 7
EXCEPT_ERR    8
EXCEPT_NO_ERR 9
EXCEPT_ERR    10
EXCEPT_ERR    11
EXCEPT_ERR    12
EXCEPT_ERR    13
EXCEPT_ERR    14
EXCEPT_NO_ERR 15
EXCEPT_NO_ERR 16
EXCEPT_ERR    17
EXCEPT_NO_ERR 18
EXCEPT_NO_ERR 19
EXCEPT_NO_ERR 20
EXCEPT_ERR    21
EXCEPT_NO_ERR 22
EXCEPT_NO_ERR 23
EXCEPT_NO_ERR 24
EXCEPT_NO_ERR 25
EXCEPT_NO_ERR 26
EXCEPT_NO_ERR 27
EXCEPT_NO_ERR 28
EXCEPT_ERR    29
EXCEPT_ERR    30
EXCEPT_NO_ERR 31

IRQ_STUB 0,  32
IRQ_STUB 1,  33
IRQ_STUB 2,  34
IRQ_STUB 3,  35
IRQ_STUB 4,  36
IRQ_STUB 5,  37
IRQ_STUB 6,  38
IRQ_STUB 7,  39
IRQ_STUB 8,  40
IRQ_STUB 9,  41
IRQ_STUB 10, 42
IRQ_STUB 11, 43
IRQ_STUB 12, 44
IRQ_STUB 13, 45
IRQ_STUB 14, 46
IRQ_STUB 15, 47

except_common:
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    push rbp
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    push rax

    mov rdi, [rsp + 15 * 8]
    mov rsi, [rsp + 16 * 8]
    extern exception_handler
    call exception_handler

    pop rax
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15

    add rsp, 16
    iretq

irq_common:
    push r15
    push r14
    push r13
    push r12
    push r11
    push r10
    push r9
    push r8
    push rbp
    push rdi
    push rsi
    push rdx
    push rcx
    push rbx
    push rax

    mov rdi, [rsp + 15 * 8]
    extern irq_handler
    call irq_handler

    pop rax
    pop rbx
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    pop r8
    pop r9
    pop r10
    pop r11
    pop r12
    pop r13
    pop r14
    pop r15

    add rsp, 16
    iretq

section .data
gdt64:
    dq 0
    dq 0x00209A0000000000
    dq 0x0000920000000000
gdt64_end:

gdt64_ptr:
    dw gdt64_end - gdt64 - 1
    dd gdt64

section .bss
align 16
stack_bottom:
    resb 16384
stack_top:

multiboot_magic: resd 1
multiboot_info:  resd 1

align 4096
pml4: resb 4096
pdpt: resb 4096
pd:   resb 4096 * 4

global __kernel_end
__kernel_end:
