global mdiv

; w rdi jest dzielna, w rsi n, w rdx dzielnik
section .text
mdiv:
    mov r9, rdx                     ;rdx bedzie na konczu trzymac reszte z dzielenia,
    xor r10, r10                    ;zatem dzielnikowi przydzielamy r9 
    xor r11, r11

    cmp r9, 0                           
    jge .positive_divider           ;jesli ujemny dzielnik, zmieniam jego znak

    not r9
    add r9, 0x1
    add r11, 0x1                    ;r11 to flaga na znak dzielnika: 1 - ujemny 0 - dodatni

.positive_divider:
    dec rsi                         ; zeby nie wyjsc poza zakres, zaczynamy od n-1
    mov rcx, rsi                    ; przechowujemy n-1 w rcx
    cmp QWORD [rdi + rsi * 8], 0    ;sprawdzamy pierwszy segment dzielnej
    jge .positive_dividend          ;gdy dzielna jest ujemna, zmieniam jej znak
    add r10, 0x1                    ;r10 to flaga na znak dzielnej: 1 - ujemny 0 - dodatni

.sign_change_dividend:
    not QWORD [rdi + rsi * 8]       ;notujemy cala dzielna, pozniej dodamy jedynke by zmienic znak
    dec rsi
    jge .sign_change_dividend

    xor edx, edx

;po negacji dodajemy jedynke, iterujemy od 0 do n-1, bo
;moze byc tak ze jedynka przechodzi do nastepnego segmentu itd
;jezeli przeszlismy przez wszystkie segmenty poza ostatnim konczymy
.adding_one_dividend:                       

    add QWORD [rdi + rdx * 8], 0x1                     
    jnc .positive_dividend          ;jezeli liczba nie zmiesci sie w segmencie dodajemy 1 do kolejnego
    inc rdx                         ;nie wyjdziemy poza zakres bo to dzialo by sie dla 0 a jest nieujemne
    jmp .adding_one_dividend

.positive_dividend:

    xor edx, edx
    mov rsi, rcx                    ;przywracamy rsi wartosc n-1                

.div_loop:                          ;zaczynamy od n-1 segmentu, iterujemy do 0
    mov rax, QWORD [rdi + rsi * 8]  ;wrzucamy segment do raxa
    div r9                          ;dzielimy rdx:rax przez dzielna
    cmp r10, r11                    ;jezeli r10 = r11, to wynik dzielenia bedzie nieujemny
    je .positive
    not rax                         ;odrazu notujemy caly wynik
.positive:
    mov [rdi + rsi * 8], rax        ;wynik dzielenia wstawiamy na swoje miejsce
    dec rsi
    jge .div_loop                    ;dopoki rsi - indeks danego segmentu >= 0 dzielimy

    cmp r10, 1                      ;r10 = 1 oznacza ujemna reszte                  
    jne .positive_remainder
    not rdx                         ;zmiana znaku reszty
    add rdx, 0x1
    
.positive_remainder:
    cmp r10, r11                    ;jezeli r10 = r11, to wynik dzielenia bedzie nieujemny
    je .positive_res

;tu sie dzieje dla ujemnego wyniku
    xor r10, r10                    ; r10 sie juz nie przyda
    inc rcx
; przechodzimy po segmentach wszystkich, jezeli 1 przechodzi
; na kolejne segmenty
.adding_one_res:                     ;po negacji dodajemy jedynke, iterujemy od 0 do n-1, bo
                                    ;jezeli przeszlismy przez wszystkie segmenty, konczymy zeby nie wyjsc                           
    add QWORD [rdi + r10 * 8], 0x1  ;poza zakres (dzieje sie to dla liczby 111...11), czyli wyniku 0    
    jnc .end2                       ;jezeli nie zmiesci sie w segmencie dodajemy 1 do kolejnego  
    inc r10
    loop .adding_one_res 

.positive_res:
;sprawdzamy czy nie wystapil nadmiar, czyli dodatni wynik spoza zakresu U2
;ostatni segment ma zapalony bit znaku wtw caly wynik jest rowny 10...00
;zauwazmy ze rcx jest rowny n - 1, bo dla nieujemnego wyniku pozostal niezmieniony
    mov rcx, QWORD [rdi + rcx * 8]
    test rcx, rcx  
    js .overflow  
    jmp .end2

.end2:
    mov rax, rdx                    
    ret

.overflow:
    xor r10, r10
    div r10                   ;wysylamy SIGFPE