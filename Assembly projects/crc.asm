global _start


SYS_OPEN equ 2
ERROR equ 1
SYS_WRITE equ 1
SYS_LSEEK equ 8
SYS_CLOSE equ 3
SYS_EXIT equ 60
MAX_LEN   equ 64
CURRENT equ 1
LEN_OF_DATALENGTH equ 2
LEN_OF_OFFSET equ 4
LAST_BYTE_OFFSET equ 7
ONE_BYTE equ 1
STDIN equ 1


section .bss
    fd: resb 8
    data_len: resb 2
    offset: resb 4
    buffer: resb 8
    reserve_buffer: resb 1
    result: resb 65

section .text

_start:

    mov rcx, [rsp]
    cmp rcx, 3      
    ; jezeli nie mamy dwoch parametrow,
    ; pliku oraz crc_poly, to blad
    jne .error_exit


    ;ustalenie dlugosci crc_polly, spacer po stringu
    mov rbx, [rsp + 24]        ; wrzucamy adres do crc_poly do rbx
    xor al, al
    cld                      ; Szukaj w kierunku większych adresów.
    mov ecx, MAX_LEN + 1     
    mov rdi, rbx            
    repne scasb             
    ; przechodzimy do konca napisu, chyba ze jest za dlugi
    jnz .error_exit          ; crc_poly byl za dlugi, to blad
    sub rdi, rbx            
    ; rdi ma adres rbx + dlugosc crc_poly + 1, a chcemy miec dlugosc
    sub edi, 1              
    mov r8d, edi             ; r8d trzyma dlugosc

    ;konwersja crc_poly ze stringa na liczbe
    ;dodaje 0 lub 1 i przesuwa w lewo w petli,
    ; aby uzyskac liczbe zamiast napisu
    xor r9d, r9d
    mov ecx, edi


.to_number:
    mov al, [rbx]
    shl r9, 1
    cmp al, '0'
    je .zero        ;nie dodajemy jedynki
    cmp al, '1'
    jne .error_exit  
    ;jezeli crc_poly ma na jakims miejscu cos innego niz 0 lub 1 to blad

    inc r9      ; r9 zawiera crc_poly

.zero:
    inc rbx
    loop .to_number
    ;przesuwanie crc na maksa w lewo
    mov cl, 64
    sub cl, r8b
    shl r9, cl

    ;otwieranie pliku
    mov rdi, [rsp + 16]         ; nazwa pliku odrazu jako parametr do sys_open
    xor esi, esi               ; read_only
    mov eax, SYS_OPEN
    syscall
    cmp rax, -4096  ; Trikowe sprawdzenie, czy wystąpił błąd, czyli czy w rax
    ja .error_close_and_exit       ; jest wartość pomiędzy -1 a -4095.
    mov [rel fd], rax


    ; r12 bedzie trzymac przesuniecie w buforze, aby adresowac poprawny bajt
    ; i jest wywolane przed readem, bo chcemy raz na caly plik
    ; zaladowac 8 bajtow do bufora xorowanego
    mov r12, LAST_BYTE_OFFSET
    xor r10d, r10d

.read:
    ;wczytanie dlugosci danych we fragmencie
    xor eax, eax ; sys_read
    mov rdi, qword [rel fd]
    mov rsi, data_len
    mov edx, LEN_OF_DATALENGTH
    syscall
    cmp rax, -4096  ; Trikowe sprawdzenie, czy wystąpił błąd, czyli czy w rax
    ja .error_close_and_exit       ; jest wartość pomiędzy -1 a -4095.


    ;wczytanie do glownego bufora na poczatku

    ; mamy 8 bajtowy bufor do operacji xor, i zapasowy jedno bajtowy,
    ; aby moc przesuwac bitowo i xorowac

    ; dlugosc danych mamy w data_len
    ; ladujemy od prawej do lewej bajtowo, ze wzgledu na big endian, w pliku
    ; pozniej wrzucimy zawartosc bufora do r15
    ; i bedzie juz w takiej kolejnosci jakiej chcemy
    ; r10 trzyma liczbe bajtow zaldowanych do bufora glownego
    ; r13 trzyma liczbe bajtow danych + 2 bajty dlugosci + 4 bajty offsetu,
    ; r12 to przesuniecie, do ladowania bitow we wlasciwe miejsce w buforze
    ; bedzie sluzyc do sprawdzenia czy
    ; nie skaczemy w to samo miejsce (koniec pliku)
    ; r14 trzyma liczbe bitow w buforze rezerwy
    ; r15 trzyma aktualne 8 bajtow, do xorowania z crc
    xor r13d, r13d
    mov r13w, WORD [rel data_len]
    add r13, 6
    mov edx, ONE_BYTE   ;bedziemy zawsze ladowac jeden bajt
    ;jezeli w tej iteracji mamy zaladowany glowny bufor,
    ; to pomijamy ladowanie do niego
    cmp r10b, 8
    je .reading_a_byte_to_a_second_buffer

.reading_first_8_bytes:
    ;jezeli skonczyly sie dane, konczymy
    ; i czytamy nastepny segment dopoki nie zaladujemy tych 8 bajtow
    cmp WORD [rel data_len], 0
    je .segment_end
    xor eax, eax    ;sys_read
    mov rsi, buffer            ;rsi to buffer + przesuniecie
    add rsi, r12
    syscall
    cmp rax, -4096
    ja .error_close_and_exit
    dec WORD [rel data_len]    ;wczytalismy 1 bajt danych
    inc r10b
    dec r12                    ;idziemy od prawej do lewej
    cmp r12, 0                 ; jak r12 < 0, to zaladowalismy bufor
    jge .reading_first_8_bytes

    ;wrzucamy do rejestru r15, zawartosc bufora z zaladowanymi 8 bajtami
    mov r15, QWORD [rel buffer]

    ;wczytanie do bufora zapasowego
.reading_a_byte_to_a_second_buffer:
    mov rsi, reserve_buffer
    cmp WORD [rel data_len], 0
    jz .segment_end
    dec WORD [rel data_len]

    mov r14d, 8
    xor eax, eax
    syscall

    cmp rax, -4096
    ja .error_close_and_exit

    ; jak mamy 8 bajtow zaladowanych w buforze,
    ; mozemy wykonywac operacje xor z crc
    ; przesuwamy wykonujemy, shl dla buffora + reserwowego i xorujemy
    ; taka kolejnosc ze wzgledu na dodatkowy
    ; wspolczynnik wielomianu (niewidoczny)
    ; aby kontynuowac xor

    ; xor loop to wykonanie operacji xor i przesuniecia 8 razy
    mov al, byte [rel reserve_buffer]


.xor_loop:
    xor ecx, ecx ; flaga na to czy xorujemy czy nie
    test r15, r15
    js .starts_with_one
    shl r15, 1
    jmp .after_one_operation

.starts_with_one:
    shl r15, 1
    inc cl

.after_one_operation:
    test al, al
    jns .potential_xor
    inc r15

.potential_xor:
    test cl, cl
    je .shrinking_reserve_buffer
    xor r15, r9

.shrinking_reserve_buffer:
    shl al, 1
    dec r14b
    jnz .xor_loop

    ;odczyt kolejnego bajtu
    jmp .reading_a_byte_to_a_second_buffer

.segment_end:
    ;odczyt przesuniecia
    xor eax, eax
    mov edx, LEN_OF_OFFSET
    mov rsi, offset
    syscall
    cmp rax, -4096
    ja .error_close_and_exit
    movsx r11 , DWORD [rel offset]

    ;sprawdzenie czy przesuwamy sie w to samo miejsce
    add r13, r11
    jz .file_has_been_read

    mov eax, SYS_LSEEK
    mov rsi, r11 ; r11 trzyma offset ustawiony na 64 bitowa wersje
    mov edx, CURRENT
    syscall
    cmp rax, -4096 
    ja .error_close_and_exit
    ;fragment odczytany
    jmp .read   

.file_has_been_read:
    ; r10 mowi nam ile bajow zostalo do zxorowania
    ;oraz w r15, mamy to ostatnie x bitow do xoru
    ; wiec w cl wrzucimy przesuniecie
    cmp r10b, 8 
    ;jezeli nie udalo nam sie zaladowac 8 bajtow
    ;to ladujemy tyle ile ich jest
    je .buffer_loaded
    mov r15, QWORD [rel buffer]
.buffer_loaded:
    shl r10b, 3   ; z bajtow na bity

    ; wykonujemy operacje xor na pozostalych bitach, juz w jednym buforze
.final_xor:
    test r15, r15
    js .starts_with_one_final
    shl r15, 1
    jmp .after_one_operation_final

.starts_with_one_final:
    shl r15, 1
    xor r15, r9
.after_one_operation_final:
    dec r10b
    jnz .final_xor

    ;niech r13 trzyma dlugosc crc polly, bedzie potrzebna do petli i wypisania
    mov r13d, r8d
    mov rdi, result

.convert_result_to_string:
    test r15, r15
    js .result_starts_with_one
    mov BYTE [rdi], '0'
    jmp .result_after_one_operation
.result_starts_with_one:
    mov BYTE [rdi], '1'
.result_after_one_operation:
    shl r15, 1
    inc rdi
    dec r13d
    jnz .convert_result_to_string

    ;dodajemy do wielomianu znak nowej linii
    mov BYTE [rdi], `\n`
    inc r8d
    ;sys_write
    mov eax, SYS_WRITE
    mov edi, STDIN
    mov rsi, result
    mov edx, r8d
    syscall
    cmp rax, -4096 
    ja .error_close_and_exit
    ;sys_close
    mov eax, SYS_CLOSE
    mov rdi, qword [rel fd]
    syscall
    cmp rax, -4096
    ja .error_exit
    ;sys_exit
    mov eax, SYS_EXIT
    xor edi, edi
    syscall

.error_close_and_exit:
    mov eax, SYS_CLOSE
    mov rdi, qword [rel fd]
    syscall
    jmp .error_exit

.error_exit:
    mov eax, SYS_EXIT
    mov edi, ERROR
    syscall
