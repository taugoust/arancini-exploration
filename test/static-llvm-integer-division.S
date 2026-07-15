.section .text
.global _start
.type _start, @function
_start:
    # Signed 32-bit division: -100 / 7 = -14.
    movl $-100, %eax
    cltd
    movl $7, %ecx
    idivl %ecx
    cmpl $-14, %eax
    jne .Lfail

    # Unsigned 32-bit division with the high bit of EDX:EAX set.
    # 0x8000000000000000 / 0x80000001 = 0xfffffffe.
    movl $0, %eax
    movl $0x80000000, %edx
    movl $0x80000001, %ecx
    divl %ecx
    cmpl $0xfffffffe, %eax
    jne .Lfail

    movl $1, %eax
    movl $1, %edi
    leaq .Lok(%rip), %rsi
    movl $3, %edx
    syscall

    movl $60, %eax
    xorl %edi, %edi
    syscall

.Lfail:
    movl $60, %eax
    movl $1, %edi
    syscall
.size _start, .-_start

.section .rodata
.Lok:
    .ascii "ok\n"
