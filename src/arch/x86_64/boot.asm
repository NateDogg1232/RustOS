global start
;This will be the 64-bit starting function
extern long_mode_start

section .text
bits 32
start:
    mov esp, stack_top

    ;We check for multiboot first
    call check_multiboot
    ;Then we check to see if CPUID is supported
    call check_cpuid
    ;And then we check to see if long mode is possible
    call check_long_mode

    ;Now that we've checked for all the abilities, we can actually do things
    ;We set up our page tables
    call set_up_page_tables
    ;And we enable our paging
    call enable_paging

    ;And to finish off the switch to long mode, we load up the GDT
    lgdt [gdt64.pointer]

    ;And we go to our 64-bit starting function
    jmp gdt64.code:long_mode_start


; Prints `ERR: ` and the given error code to screen and hangs.
; parameter: error code (in ascii) in al
error:
    mov dword [0xb8000], 0x4f524f45
    mov dword [0xb8004], 0x4f3a4f52
    mov dword [0xb8008], 0x4f204f20
    mov byte  [0xb800a], al
    hlt

check_multiboot:
    ;Checks for a multiboot magic number
    cmp eax, 0x2BADB002
    jne .no_multiboot
ret
    .no_multiboot:
        mov al, "0"
        jmp error

check_cpuid:
    ; Check if CPUID is supported by attempting to flip the ID bit (bit 21)
    ; in the FLAGS register. If we can flip it, CPUID is available.

    ; Copy FLAGS in to EAX via stack
    pushfd  ;Pushes EFLAGS
    pop eax

    ; Copy to ECX as well for comparing later on
    mov ecx, eax

    ; Flip the ID bit
    xor eax, 1 << 21

    ; Copy EAX to FLAGS via the stack
    push eax
    popfd

    ; Copy FLAGS back to EAX (with the flipped bit if CPUID is supported)
    pushfd
    pop eax

    ; Restore FLAGS from the old version stored in ECX (i.e. flipping the
    ; ID bit back if it was ever flipped).
    push ecx
    popfd

    ; Compare EAX and ECX. If they are equal then that means the bit
    ; wasn't flipped, and CPUID isn't supported.
    cmp eax, ecx
    je .no_cpuid
ret
    .no_cpuid:
        mov al, "1"
        jmp error


check_long_mode:
    ; test if extended processor info in available
    mov eax, 0x80000000    ; implicit argument for cpuid
    cpuid                  ; get highest supported argument
    cmp eax, 0x80000001    ; it needs to be at least 0x80000001
    jb .no_long_mode       ; if not, it doesn't support the argument to even check for long mode.

    ; use extended info to test if long mode is available
    mov eax, 0x80000001    ; argument for extended processor info
    cpuid                  ; returns various feature bits in ecx and edx
    test edx, 1 << 29      ; test if the LM-bit is set in the D-register
    jz .no_long_mode       ; If it's not set, there is no long mode
ret
    .no_long_mode:
        mov al, "2"
        jmp error

set_up_page_tables:
    ;Let's start with the P4 table.
    ;We first need to map the P3 table to the P4 table
    mov eax, p3_table   ;Get the address
    or eax, 0b11        ;Set to present + writable
    mov [p4_table], eax ;And store it in the table

    ;And we move onto the P3 table.
    ;We need to map our P2 table to the P3 table.
    ;We just follow the same steps as we took with the P4 table
    mov eax, p2_table
    or eax, 0b11
    mov [p3_table], eax

    ;And now we map the P2 table.

    mov ecx, 0  ;Set up our counter for our loop
    .map_p2_table:
        ;Let's use huge pages.
        ;We first need to translate our counter into an address to put in a page
        ;This is pretty simple
        ;We'll use eax to store our entry
        mov eax, 0x200000   ;We load up 2MB
        ;Mul will multiply the argument by eax and store it in eax
        mul ecx             ;And we multiply this by our counter
        ;Boom, we now have an address
        ;Now we or that with our flags
        or eax, 0b10000011 ;present + writable + huge
        ;This next instruction looks complicated, but it's not.
        ;This is just moving that entry we just made into the table
        ;Each entry is 8 bytes long, so we multiply our counter by 8 to
        ;   compensate
        mov [p2_table + ecx * 8], eax

        ;Now let's do our normal looping stuff
        inc ecx             ;We increment our counter
        cmp ecx, 512        ;Then we check to see if we've mapped the whole
                            ;   table. P2 is 512 entries
        jne .map_p2_table   ;If not, we continue the loop

ret

enable_paging:
    ;Let's enable paging now
    ;We start by loading our P4 table into cr3.
    mov eax, p4_table
    mov cr3, eax

    ;And now we enable PAE
    ;Why? Well, technically, long mode is an extension of PAE, so we need that
    ;The PAE flag is in cr4
    mov eax, cr4
    or eax, 1<<5
    mov cr4, eax

    ;Now we read from the Model Specific Registers.
    ;"Woah woah woah, don't we need to check?"
    ;Nah, if we've got long mode, we of course have MSRs, since they were
    ;   introduced with the first Pentium
    ;So let's check them
    ;First we need to get the Extended Feature Enable Register (EFER)
    ;Since this register was added for long mode, we don't need to check for
    ;   its availability
    mov ecx, 0xC0000080 ;This is the address of the EFER
    rdmsr   ;And this is all we need to do to read it. It places the result in eax
    ;Now we need to set the long mode bit in the EFER MSR
    or eax, 1<<8    ;Bit 8 is the long mode enable (LME) bit
    wrmsr           ;And we write it in. It takes eax

    ;Even though we have all this stuff set up, it doesn't switch to long mode
    ;   until we actually have paging enabled, since it is part of the long mode
    ;   specification
    ;This is pretty easy. Like many things before, we just need to set a bit
    ;This time its the Page Enable (PE) bit in the cr0 register
    mov eax, cr0    ;We copy cr0 so we can modify it
    or eax, 1<<31   ;Bit 31 of cr0 is the PE bit
    mov cr0, eax    ;And we write it back

    ;That's it. We are now in long mode, kinda. No GDT means we are in 32-bit
    ;   compatability mode
ret




section .rodata
;We need a GDT in order to actually get into long mode
gdt64:
    dq 0    ;Zero entry. Each GDT requires one entry to be 0. IDK why.
    ;Our code segment. This consists of the flags:
    ;   bit 43: Executable (1 for code segment 0 for data segment)
    ;   bit 44: Descriptor Type (Should be 1 for both data and code segments)
    ;   bit 47: Present (Must be 1 for valid segments)
    ;   bit 53: 64-bit (Must be 1 for 64-bit segments)
    ;   bit 54: 32-bit (Must be 0 for 64-bit segments)
.code: equ $ - gdt64
    dq (1<<43) | (1<<44) | (1<<47) | (1<<53)
.pointer:
    ;This is the pointer for the GDT
    ;GDT size
    dw $ - gdt64 - 1
    dq gdt64

section .bss
align 4096
p4_table:
    resb 4096
p3_table:
    resb 4096
p2_table:
    resb 4096
;4KiB stack
stack_bottom:
    resb 4096
stack_top:
