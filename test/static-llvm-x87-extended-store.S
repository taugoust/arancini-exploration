.section .text
.global _start
.type _start, @function
_start:
    fld1
    fstpt value(%rip)

    cmpw $0x3fff, value+8(%rip)
    jne .Lfail
    movabsq $0x8000000000000000, %rax
    cmpq %rax, value(%rip)
    jne .Lfail

    movl $1, %eax
    movl $1, %edi
    leaq message(%rip), %rsi
    movl $3, %edx
    syscall

    xorl %edi, %edi
    jmp .Lexit

.Lfail:
    movl $1, %edi

.Lexit:
    movl $60, %eax
    syscall
.size _start, .-_start

.section .rodata
message:
    .ascii "ok\n"

.section .data
.p2align 4
value:
    .zero 16
