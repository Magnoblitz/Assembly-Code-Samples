; nasm -f win64 -o rendering_demo.o rendering_demo.asm && gcc -o rendering_demo.exe rendering_demo.o image_funcs.o -luser32 -lkernel32 -lgdi32 -mwindows && rendering_demo.exe



; NOTE: all colors are in form 0xAARRGGBB (alpha, red, green, blue) unless otherwise stated



; tell the system how to interpret the code
bits 64
default rel



; set the entry point
global main



; default externs:

extern ExitProcess
extern GetModuleHandleA
extern printf
extern GetLastError
extern CreateWindowExA
extern RegisterClassExA
extern DefWindowProcA
extern ShowWindow
extern SetFocus
extern GetProcessHeap
extern HeapAlloc
extern HeapFree
extern QueryPerformanceFrequency
extern QueryPerformanceCounter
extern PeekMessageA
extern TranslateMessage
extern DispatchMessageA
extern GetDC
extern StretchDIBits
extern UpdateWindow
extern QueryPerformanceCounter
extern QueryPerformanceFrequency
extern SetTextColor
extern TextOutA
extern AddFontResourceExA 
extern CreateFontA
extern SelectObject
extern BeginPaint
extern EndPaint
extern GetClientRect
extern SetPixel
extern CreateCompatibleDC      
extern CreateCompatibleBitmap
extern BitBlt
extern CreateDIBSection
extern wsprintfA
extern SetBkMode
extern LoadImageA



; my custom externs:

extern load_image_data
extern load_scaled_image_data



; definitions:

%define WINDOW_WIDTH (672)
%define WINDOW_HEIGHT (672)



; structs:

struc image_data
    ; 271 bytes total

    filename resb 255
    image_width resd 1
    image_height resd 1
    pixel_data resq 1
endstruc

struc image_drawing_data
    ; 23 bytes total

    image_to_draw_ptr resq 1 ; ptr to image_data
    image_flip_x resb 1      ; 0 = false, 1 = true
    image_flip_y resb 1      ; 0 = false, 1 = true

    image_r_shift resw 1     ; -255 - 255 (shifts red channel)
    image_g_shift resw 1     ; -255 - 255 (shifts green channel)
    image_b_shift resw 1     ; -255 - 255 (shifts blue channel)

    image_opacity resb 1     ; opacity = 0 makes the image fully invisible, opacity = 255 makes the image fully opaque (no change)

    image_h_shift resw 1     ; -255 - 255 (shifts hue)
    image_s_shift resw 1     ; -255 - 255 (shifts saturation)
    image_v_shift resw 1     ; -255 - 255 (shifts value)
endstruc

struc gradient_data
    ; 16 bytes total

    gradient_top_left_color resb 4
    gradient_top_right_color resb 4
    gradient_btm_left_color resb 4
    gradient_btm_right_color resb 4
endstruc

struc stripes_data
    ; 13 bytes total

    stripes_horizontal resb 1
    stripe_num resd 1
    stripe_color1 resb 4
    stripe_color2 resb 4
endstruc

struc checker_data
    ; 9 bytes total

    checker_num resb 1
    checker_color1 resb 4
    checker_color2 resb 4
endstruc

struc circle_data
    ; 4 bytes total

    circle_color resb 4
endstruc

struc squircle_data
    ; 12 bytes total

    squircle_color resb 4
    squircle_corner_amount resq 1   ; sd number
endstruc

struc pos_and_size
    ; 32 bytes total

    x_pos resq 1
    y_pos resq 1
    width resq 1
    height resq 1
endstruc



; .data variables:

segment .data
    ; Names:
    class_name db "My Class", 0
    title db "Rendering Demo", 0
    icon_path db "icon.ico", 0

    ; Rendering variables:
    SCREEN_WIDTH equ 672
    SCREEN_HEIGHT equ 672
    SCREEN_PIXELS equ SCREEN_WIDTH * SCREEN_HEIGHT
    SCREEN_BYTES equ SCREEN_PIXELS * 4
    PIXELS dq 0

    ; Game state variables:
    IS_RUNNING: dq 0
    GAME_OVER: db 0

    ; Timer variables:
    TIMER_CURR dq 0
    TIMER_START dq 0
    TIMER_FREQ dq 0
    FLOAT_ONE_OVER_FRAMETIME:
        dq 0
        dq 0

    ; Time variables:
    freq dq 0            
    start_time dq 0         
    current_time dq 0    
    last_time dq 0
    elapsed dq 0 
    delta_time dq 0

    ; Window pointers:
    hWnd dq 0
    front_buffer_hdc dq 0
    back_buffer_hdc dq 0
    back_buffer_dib dq 0
    hIcon dq 0

    ; Math variables:
    natural_log_two dq 0.69314718056
    abs_mask_sd dq 0x7FFFFFFFFFFFFFFF

    ; Printing variables:
    print_float db "%f", 0xd, 0xa, 0
    error_string db "Error Code: %d", 0xd, 0xa, 0

    ; Structs:
    BMP:
        bmp_biSize             dd 40             ; 4 bytes
        bmp_biWidth            dd SCREEN_WIDTH   ; 4 bytes
        bmp_biHeight           dd SCREEN_HEIGHT  ; 4 bytes
        bmp_biPlanes           dw 1              ; 2 bytes
        bmp_biBitCount         dw 32             ; 2 bytes
        bmp_biCompression      dd 0              ; 4 bytes
        bmp_biSizeImage        dd 0              ; 4 bytes
        bmp_biXPelsPerMeter    dd 0              ; 4 bytes
        bmp_biYPelsPerMeter    dd 0              ; 4 bytes
        bmp_biClrUsed          dd 0              ; 4 bytes
        bmp_biClrImportant     dd 0              ; 4 bytes
        bmp_rgbBlue            db 0xFF           ; 1 byte
        bmp_rgbGreen           db 0xFF           ; 1 byte
        bmp_rgbRed             db 0xFF           ; 1 byte
        bmp_rgbReserved        db 0x00           ; 1 byte

    PAINTSTRUCT:
        ps_hdc           dq 0             ; 8 bytes
        ps_fErase        dd 0             ; 4 bytes
        ps_rcPaint       times 4 dd 0     ; 16 bytes
        ps_fRestore      dd 0             ; 4 bytes
        ps_fIncUpdate    dd 0             ; 4 bytes
        ps_rgbReserved   times 32 db 0    ; 32 bytes

    flamingo_image:
        istruc image_data
            at filename, db "images/flamingo.png"
        iend
   
    ufo_image:
        istruc image_data
            at filename, db "images/ufo.png"
        iend

    man_standing_image:
        istruc image_data
            at filename, db "images/man_standing.png"
        iend

    star_image:
        istruc image_data
            at filename, db "images/star.png"
        iend



; start of actual code:

segment .text

main:
    ; load the image data
    lea rcx, flamingo_image
    call load_image_data

    lea rcx, ufo_image
    call load_image_data

    lea rcx, man_standing_image
    call load_image_data

    lea rcx, star_image
    call load_image_data



    ; get and store frequency and start time
    lea rcx, [freq]   
    call QueryPerformanceFrequency
    lea rcx, [start_time] 
    call QueryPerformanceCounter
    mov rax, qword [start_time]
    mov qword [last_time], rax

    ; reserve stack space
    sub rsp, 264

    ; get the module handle and store it in [rsp + 96]
    xor ecx, ecx
    call GetModuleHandleA
    mov qword [rsp + 96], rax

    ; load the icon image
    xor rcx, rcx
    lea rdx, [icon_path]
    mov r8, 1
    mov r9, 0
    mov qword [rsp + 32], 0
    mov qword [rsp + 40], 0x00000010
    call LoadImageA
    mov [hIcon], rax

    ; register the class for the window
    mov dword [rsp + 104], 80
    mov dword [rsp + 108], 35
    lea rax, [rel WndProc]
    mov qword [rsp + 112], rax
    mov qword [rsp + 120], 0
    mov qword rax, [rsp + 96]
    mov qword [rsp + 128], rax

    mov rax, [hIcon]      
    mov [rsp + 136], rax

    mov qword [rsp + 144], 0  ; cursor
    mov qword [rsp + 152], 0
    mov qword [rsp + 160], 0
    lea rax, [rel class_name]
    mov qword [rsp + 168], rax
    mov qword [rsp + 176], 0
    lea rcx, [rsp + 104]
    call RegisterClassExA

    ; if the class is not correctly registered, call a breakpoint
    cmp qword rax, 0
    jne RegisterClass_post_branch
    int 3

RegisterClass_post_branch:
    ; create the window
    mov rcx, 262144
    lea rdx, [rel class_name]
    lea r8, [rel title]
    mov qword r9, 0x100A0000
    mov qword [rsp + 32], 1280 - WINDOW_WIDTH
    mov qword [rsp + 40], 0
    mov qword [rsp + 48], WINDOW_WIDTH
    mov qword [rsp + 56], WINDOW_HEIGHT
    xor eax, eax
    mov qword [rsp + 64], rax
    mov qword [rsp + 72], rax
    mov qword rax, [rsp + 96]
    mov qword [rsp + 80], rax
    xor eax, eax
    mov qword [rsp + 88], rax
    call CreateWindowExA

    ; if the window is not correctly created, call a breakpoint
    cmp qword rax, 0
    jne CreateWindow_post_branch
    int 3

CreateWindow_post_branch:
    ; show the previously created window
    mov [hWnd], rax
    mov rcx, rax
    mov rdx, 5
    call ShowWindow

    ; save the hdc in front_buffer_hdc
    mov rcx, [hWnd]
    call GetDC
    mov [front_buffer_hdc], rax

    ; set the focus on the window
    mov rcx, [hWnd]
    call SetFocus

    ; get the handle to the process heap
    lea rcx, [rsp + 192]
    xor rax, rax
    mov qword [rcx], rax
    mov qword [rcx + 8], rax
    mov qword [rcx + 16], rax
    mov qword [rcx + 24], rax
    mov qword [rcx + 32], rax
    mov qword [rcx + 40], rax
    mov qword [rel IS_RUNNING], 1
    call GetProcessHeap

    ; allocate space for the screen bytes on the heap
    mov qword [rsp + 240], rax
    mov rcx, rax
    mov edx, 8
    mov r8, SCREEN_BYTES
    call HeapAlloc

    ; store values in the variables
    mov qword [rel PIXELS], rax
    mov dword [rel bmp_biSize], 44
    mov dword [rel bmp_biWidth], SCREEN_WIDTH
    mov dword [rel bmp_biHeight], SCREEN_HEIGHT
    mov byte  [rel bmp_biPlanes], 1
    mov byte  [rel bmp_biBitCount], 32
    mov dword [rel bmp_biCompression], 0

    ; get and store the timer frequency
    lea rcx, [rel TIMER_FREQ]
    call QueryPerformanceFrequency
    mov qword rax, [rel TIMER_FREQ]

    ; calculate timer start and (1 / frame time)
    cvtsi2sd xmm1, eax

    mov rax, 1
    cvtsi2sd xmm0, rax

    divsd xmm0, xmm1
    movsd [rel TIMER_FREQ], xmm0
    lea rcx, [rel TIMER_START]
    call QueryPerformanceCounter
    call get_time
    movsd xmm6, xmm0
    movsd xmm7, [rel FLOAT_ONE_OVER_FRAMETIME]
    xorps xmm8, xmm8


setup_buffers:
    ; create the back buffer
    mov rcx, [front_buffer_hdc]
    call CreateCompatibleDC
    mov [back_buffer_hdc], rax

    ; create a device independent bitmap (DIB) for the back buffer
    mov rcx, [back_buffer_hdc]
    lea rdx, [rel BMP]
    mov r8, 0
    lea r9, [rel back_buffer_dib]
    mov dword [rsp +  32], 0
    mov dword [rsp + 40], 0
    call CreateDIBSection
    mov [back_buffer_dib], rax

    ; select the dib for the back buffer
    mov rcx, [back_buffer_hdc]
    mov rdx, [back_buffer_dib]
    call SelectObject



; start the game loop:

while_is_running:
    ; calculate current time (in seconds)
    lea rcx, [current_time]
    call QueryPerformanceCounter

    ; calculate elapsed (time since start of program, in seconds)
    mov rax, qword [current_time]
    sub rax, qword [start_time]
    cvtsi2sd xmm0, rax

    ; set the freq to a large number to fix a glitch
    mov rax, 10000000
    mov [freq], rax
  
    ; calculate elapsed
    mov rax, qword [freq]
    cvtsi2sd xmm1, rax    
    divsd xmm0, xmm1
    movsd qword [elapsed], xmm0

    ; calculate delta time (in seconds)
    mov rax, qword [current_time]
    sub rax, qword [last_time]
    cvtsi2sd xmm0, rax
    mov rax, qword [freq]
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1
    movsd qword [delta_time], xmm0

    ; last time = current time
    mov rax, qword [current_time]
    mov qword [last_time], rax

while_peek_msg:  
    ; if is_running is false, end the program
    cmp qword [rel IS_RUNNING], 0
    je while_is_running_exit

    ; peek the next message
    lea rcx, [rsp + 192] 
    xor rdx, rdx
    xor r8, r8
    xor r9, r9
    mov qword [rsp + 32], 1
    call PeekMessageA   
             
    ; if there is no new message, exit the peek msg loop
    test eax, eax
    jle while_peek_msg_exit

    ; translate the message
    lea rcx, [rsp + 192]
    call TranslateMessage

    ; dispatch the message
    lea rcx, [rsp + 192]
    call DispatchMessageA

    ; repeat the loop
    jmp while_peek_msg

while_peek_msg_exit:
    call get_time
    movsd xmm1, xmm0
    subsd xmm1, xmm6
    addsd xmm8, xmm1
    movsd xmm6, xmm0

game_tick:
    ; clear the pixels array
    xor eax, eax
    mov dword ecx, SCREEN_PIXELS
    mov qword rdi, [rel PIXELS]
    rep stosd
                
    ; fill the screen with black
    mov rcx, 0xFF000000
    call fill_screen



    ; draw background (black and green vertical gradient)
    sub rsp, 48

    mov rax, 0xFF000000
    mov [rsp + gradient_top_left_color], rax
    mov rax, 0xFF000000
    mov [rsp + gradient_top_right_color], rax
    mov rax, 0xFF00331A
    mov [rsp + gradient_btm_left_color], rax
    mov rax, 0xFF00331A
    mov [rsp + gradient_btm_right_color], rax

    lea rcx, [rsp]
    call fill_screen_gradient

    add rsp, 48


 
    ; draw ground at bottom of screen
    mov rcx, 0xFF000000
    mov rdx, 0
    mov r8, 0
    mov r9, SCREEN_WIDTH 
    mov r10, 125
    call draw_rect



    ; reserve stack space
    sub rsp, 56


   
    ; draw color-changing flamingo on right of screen
    lea rbx, [flamingo_image]
    mov [rsp + image_to_draw_ptr], rbx

    mov byte [rsp + image_flip_x], 0
    mov byte [rsp + image_flip_y], 0

    mov word [rsp + image_r_shift], 0
    mov word [rsp + image_g_shift], 0
    mov word [rsp + image_b_shift], 0

    mov byte [rsp + image_opacity], 255

    ; calculate flamingo hue
    movsd xmm0, [elapsed]
    mov rbx, 100
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mov rbx, 255
    cvtsi2sd xmm1, rbx
    
    ; modulo
    movsd xmm2, xmm0
    divsd xmm2, xmm1        
    roundsd xmm3, xmm2, 3  
    mulsd xmm3, xmm1        
    subsd xmm0, xmm3
    
    cvtsd2si rbx, xmm0
    mov word [rsp + image_h_shift], bx
    mov word [rsp + image_s_shift], 150
    mov word [rsp + image_v_shift], 0

    ; set the pos_and_size
    mov qword [rsp + 24 + x_pos], 425
    mov qword [rsp + 24 + y_pos], 97
    mov qword [rsp + 24 + width], 175
    mov qword [rsp + 24 + height], 175

    ; load inputs and draw the flamingo
    lea rcx, [rsp]
    lea rdx, [rsp + 24]
    call draw_image



    ; draw man standing on the ground
    lea rbx, [man_standing_image]
    mov [rsp + image_to_draw_ptr], rbx

    mov byte [rsp + image_flip_x], 0
    mov byte [rsp + image_flip_y], 0

    ; calculate green shift for man
    sub rsp, 8
    mov rbx, [elapsed]
    mov [rsp], rbx
    fld qword [rsp]
    fsin
    fstp qword [rsp]
    movsd xmm0, [rsp]
    add rsp, 8

    mov rbx, 15
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mov rbx, 15
    cvtsi2sd xmm1, rbx
    subsd xmm1, xmm0
 
    cvtsd2si rbx, xmm1

    mov word [rsp + image_r_shift], 0
    mov word [rsp + image_g_shift], bx
    mov word [rsp + image_b_shift], 0

    mov byte [rsp + image_opacity], 255

    ; calculate saturation shift for man
    sub rsp, 8
    mov rbx, [elapsed]
    mov [rsp], rbx
    fld qword [rsp]
    fsin
    fstp qword [rsp]
    movsd xmm0, [rsp]
    add rsp, 8

    mov rbx, 20
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mov rbx, 20
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
 
    cvtsd2si rbx, xmm0

    mov word [rsp + image_h_shift], 0
    mov word [rsp + image_s_shift], bx

    ; calculate value shift for man
    sub rsp, 8
    mov rbx, [elapsed]
    mov [rsp], rbx
    fld qword [rsp]
    fsin
    fstp qword [rsp]
    movsd xmm0, [rsp]
    add rsp, 8

    mov rbx, 50
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mov rbx, 50
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
 
    cvtsd2si rbx, xmm0

    mov word [rsp + image_v_shift], bx

    ; set the pos_and_size
    mov qword [rsp + 24 + x_pos], 100
    mov qword [rsp + 24 + y_pos], 85
    mov qword [rsp + 24 + width], 160
    mov qword [rsp + 24 + height], 248

    ; load inputs and draw the man
    lea rcx, [rsp]
    lea rdx, [rsp + 24]
    call draw_image




    ; draw ufo flying in the sky
    lea rbx, [ufo_image]
    mov [rsp + image_to_draw_ptr], rbx

    mov byte [rsp + image_flip_x], 0
    mov byte [rsp + image_flip_y], 0

    mov word [rsp + image_r_shift], 0
    mov word [rsp + image_g_shift], 0
    mov word [rsp + image_b_shift], 0

    mov byte [rsp + image_opacity], 255

    mov word [rsp + image_h_shift], 0
    mov word [rsp + image_s_shift], 0
    mov word [rsp + image_v_shift], -50

    ; calculate y_pos for ufo
    sub rsp, 8
    mov rbx, [elapsed]
    mov [rsp], rbx
    fld qword [rsp]
    fsin
    fstp qword [rsp]
    movsd xmm0, [rsp]
    add rsp, 8

    mov rbx, 75
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mov rbx, 425
    cvtsi2sd xmm1, rbx
    addsd xmm0, xmm1
 
    cvtsd2si rbx, xmm0

    ; set the pos_and_size
    mov qword [rsp + 24 + x_pos], 65
    mov qword [rsp + 24 + y_pos], rbx
    mov qword [rsp + 24 + width], 206
    mov qword [rsp + 24 + height], 88

    ; load inputs and draw the ufo
    lea rcx, [rsp]
    lea rdx, [rsp + 24]
    call draw_image



    ; draw star in the sky
    lea rbx, [star_image]
    mov [rsp + image_to_draw_ptr], rbx

    mov byte [rsp + image_flip_x], 0
    mov byte [rsp + image_flip_y], 0

    mov word [rsp + image_r_shift], 0
    mov word [rsp + image_g_shift], 0
    mov word [rsp + image_b_shift], 0

    ; calculate opacity for star
    sub rsp, 8
    mov rbx, [elapsed]
    mov [rsp], rbx
    fld qword [rsp]
    fsin
    fstp qword [rsp]
    movsd xmm0, [rsp]
    add rsp, 8

    mov rbx, 75
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mov rbx, 180
    cvtsi2sd xmm1, rbx
    addsd xmm0, xmm1
 
    cvtsd2si rbx, xmm0

    mov byte [rsp + image_opacity], bl

    mov word [rsp + image_h_shift], 0
    mov word [rsp + image_s_shift], 0
    mov word [rsp + image_v_shift], 0

    ; calculate scale for star
    sub rsp, 8
    mov rbx, [elapsed]
    mov [rsp], rbx
    fld qword [rsp]
    fsin
    fstp qword [rsp]
    movsd xmm0, [rsp]
    add rsp, 8

    mov rbx, 4
    cvtsi2sd xmm1, rbx
    addsd xmm0, xmm1
    mov rbx, 2
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mov rbx, 5
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1

    ; calculate width
    mov rbx, 149
    cvtsi2sd xmm1, rbx
    mulsd xmm1, xmm0
    cvtsd2si rbx, xmm1
    mov [rsp + 24 + width], rbx

    ; calculate x-pos
    mov rbx, 2
    cvtsi2sd xmm2, rbx
    divsd xmm1, xmm2
    mov rbx, 500
    cvtsi2sd xmm2, rbx
    subsd xmm2, xmm1
    cvtsd2si rbx, xmm2
    mov [rsp + 24 + x_pos], rbx

    ; calculate height
    mov rbx, 129
    cvtsi2sd xmm1, rbx
    mulsd xmm1, xmm0
    cvtsd2si rbx, xmm1
    mov [rsp + 24 + height], rbx

    ; calculate y-pos
    mov rbx, 2
    cvtsi2sd xmm2, rbx
    divsd xmm1, xmm2
    mov rbx, 500
    cvtsi2sd xmm2, rbx
    subsd xmm2, xmm1
    cvtsd2si rbx, xmm2
    mov [rsp + 24 + y_pos], rbx

    ; load inputs and draw the ufo
    lea rcx, [rsp]
    lea rdx, [rsp + 24]
    call draw_image

    ; reset stack
    add rsp, 56













    

    ; copy the pixels array to the back buffer
    mov rcx, [back_buffer_hdc]
    xor rdx, rdx
    xor r8, r8
    mov qword r9, SCREEN_WIDTH
    mov qword rax, SCREEN_HEIGHT
    mov qword [rsp + 32], rax
    mov qword [rsp + 40], 0
    mov qword [rsp + 48], 0
    mov qword rax, SCREEN_WIDTH
    mov qword [rsp + 56], rax
    mov qword rax, SCREEN_HEIGHT
    mov qword [rsp + 64], rax
    mov qword rax, [rel PIXELS]
    mov qword [rsp + 72], rax
    lea rax, [rel BMP]
    mov qword [rsp + 80], rax
    mov qword [rsp + 88], 0
    mov qword [rsp + 96], 0x00CC0020 
    call StretchDIBits

    ; copy the back buffer to the front buffer              
    mov rcx, [front_buffer_hdc]
    xor rdx, rdx
    xor r8, r8
    mov r9, SCREEN_WIDTH
    mov qword [rsp + 32], SCREEN_HEIGHT
    mov rax, [back_buffer_hdc]
    mov [rsp + 40], rax
    mov qword [rsp + 48], 0
    mov qword [rsp + 56], 0
    mov qword [rsp + 64], 0x00CC0020 
    call BitBlt



game_tick_exit:
    ; update the window and repeat the game loop
    mov qword rcx, [hWnd]
    call UpdateWindow
    jmp while_is_running

while_is_running_exit:
    ; free the pixels heap
    mov qword rcx, [rsp + 240]
    xor rdx, rdx
    mov qword r8, [rel PIXELS]
    call HeapFree
       
    ; clear rax and return
    xor rax, rax
    call ExitProcess



WndProc:
    cmp edx, 15
    je WM_PAINT

    cmp edx, 16
    je WM_CLOSE

    jmp DefWindowProcA

WM_PAINT:
    ; push rdi onto the stack
    push rdi

    ; push the rcx (hwnd) onto the stack
    push rcx

    ; rcx already has hwnd
    lea rdx, [rel PAINTSTRUCT]
    call BeginPaint

    ; pop the hwnd into rcx from the stack
    pop rcx
    lea rdx, [rel PAINTSTRUCT]
    call EndPaint

    ; restore rdi and return
    pop rdi
    ret

WM_CLOSE:
    ; set is_running to false and return
    mov qword [rel IS_RUNNING], 0
    xor eax, eax
    ret





; Math functions:

calculate_ln:
    ; inputs:
    ; rcx = x

    mov rax, 0

    movq xmm0, rcx
    cvtsi2sd xmm1, rax
    comisd xmm0, xmm1
    jg calculate_ln_normal

    mov rax, 1
    cvtsi2sd xmm1, rax
    comisd xmm0, xmm1
    jnz calculate_ln_normal

    mov rax, 0
    ret

calculate_ln_normal:
    ; allocate space for 2 ints and 2 sd numbers in the stack
    sub rsp, 32

    ; find a number n that when multiplied by x gives a number in the range 1 - 2
    mov qword [rsp + 24], 0     ; this is where n will be stored

    mov rax, 1
    cvtsi2sd xmm1, rax
    comisd xmm0, xmm1
    jb calculate_ln_less_than_one

    mov rax, 2 
    cvtsi2sd xmm1, rax
    comisd xmm0, xmm1
    jbe calculate_ln_setup

calculate_ln_greater_than_two:
    ; n -= 1
    mov rax, [rsp + 24]
    sub rax, 1
    mov [rsp + 24], rax

    ; x /= 2
    mov rax, 2
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1
    
    ; if x < 2, continue, else return
    comisd xmm0, xmm1
    jbe calculate_ln_setup
    jmp calculate_ln_greater_than_two

calculate_ln_less_than_one:
    ; n += 1
    mov rax, [rsp + 24]
    add rax, 1
    mov [rsp + 24], rax

    ; x *= 2
    mov rax, 2
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    
    ; if x > 1, continue, else return
    mov rax, 1
    cvtsi2sd xmm1, rax
    comisd xmm0, xmm1
    jge calculate_ln_setup
    jmp calculate_ln_less_than_one

calculate_ln_setup:
    ; xmm0 = (x - 1)
    mov rax, 1
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1

    mov qword [rsp], 1      ; iterator
    movsd [rsp + 8], xmm0  ; (x - 1)
    movsd [rsp + 16], xmm0 ; (x - 1) ^ iterator

calculate_ln_loop:
    mov rax, [rsp]
    add rax, 1
    mov [rsp], rax

    cmp rax, 25
    jg end_calculate_ln

    ; xmm1 = (x - 1) ^ (iterator)
    movsd xmm1, [rsp + 16]
    movsd xmm2, [rsp + 8]
    mulsd xmm1, xmm2
    movsd [rsp + 16], xmm1

    test rax, 1
    jnz calculate_ln_odd_iter

    ; even iterator
    mov rax, [rsp]
    cvtsi2sd xmm2, rax
    divsd xmm1, xmm2
    subsd xmm0, xmm1        

    jmp calculate_ln_loop

calculate_ln_odd_iter:
    ; odd iterator
    mov rax, [rsp]
    cvtsi2sd xmm2, rax
    divsd xmm1, xmm2
    addsd xmm0, xmm1

    jmp calculate_ln_loop
    
end_calculate_ln:
    ; subtract the correction (n * ln2)
    mov rax, [rsp + 24]
    cvtsi2sd xmm1, rax
    movq xmm2, [natural_log_two]
    mulsd xmm1, xmm2
    subsd xmm0, xmm1
  
    ; move the answer into rax
    movq rax, xmm0

    ; reset the stack and return
    add rsp, 32
    ret




calculate_e_to_power:
    ; inputs:
    ; rcx = x

    mov rax, 0
 
    movq xmm0, rcx
    xorps xmm1, xmm1
    comisd xmm0, xmm1
    jnz calculate_e_to_power_normal

    ; x = 0, so e ^ x = 1
    mov rax, 1
    ret

calculate_e_to_power_normal:
    ; allocate space for 2 int and 2 sd numbers in the stack
    sub rsp, 32

    mov qword [rsp], 0       ; iterator
    movsd [rsp + 8], xmm0   ; x
    mov rax, 1
    cvtsi2sd xmm1, rax
    movsd [rsp + 16], xmm1  ; x ^ iterator
    mov qword [rsp + 24], 1 ; iterator! (factorial)

    ; xmm0 starts at 1
    mov rax, 1
    cvtsi2sd xmm0, rax

calculate_e_to_power_loop:
    mov rax, [rsp]
    add rax, 1
    mov [rsp], rax
    cmp rax, 25
    jge end_calculate_e_to_power

    ; xmm1 = x ^ iterator
    movsd xmm1, [rsp + 16]
    movsd xmm2, [rsp + 8]
    mulsd xmm1, xmm2
    movsd [rsp + 16], xmm1

    ; xmm2 = iterator!
    mov rax, [rsp + 24]
    imul rax, [rsp]
    mov [rsp + 24], rax
    cvtsi2sd xmm2, rax

    divsd xmm1, xmm2
    addsd xmm0, xmm1

    jmp calculate_e_to_power_loop

end_calculate_e_to_power:
    ; move the result to rax
    movq rax, xmm0

    ; reset the stack and return
    add rsp, 32
    ret
    


calculate_x_to_power_y:
    ; inputs:
    ; rcx = x
    ; rdx = y

    movq xmm0, rcx
    xorps xmm1, xmm1
    comisd xmm0, xmm1
    jnz calculate_x_to_power_y_not_zero

    mov rax, 0
    ret

calculate_x_to_power_y_not_zero:
    mov rax, 1
    cvtsi2sd xmm1, rax
    comisd xmm0, xmm1
    jnz calculate_x_to_power_y_not_one
 
    mov rax, 1
    ret

calculate_x_to_power_y_not_one:
    ; rax = ln(x)
    call calculate_ln
 
    ; xmm0 = y * ln(x)
    movq xmm0, rax
    movq xmm1, rdx
    mulsd xmm0, xmm1

    ; store rcx in the stack
    push rcx

    ; rax = e ^ (y * ln(x))
    movq rcx, xmm0
    call calculate_e_to_power

    ; restore rcx and return
    pop rcx
    ret




rgb_to_hsv:
    ; https://www.rapidtables.com/convert/color/rgb-to-hsv.html

    ; inputs:
    ; rcx = rgb color in form 0xAARRGGBB

    ; store registers in stack
    push rbx
    push r8
    push r9
    push r10

    sub rsp, 32
    ; [rsp]      = cmax (8 bytes, qword)
    ; [rsp + 8]  = cmin (8 bytes, qword)
    ; [rsp + 16] = delta (8 bytes, qword)
    
    ; [rsp + 24] = hue        (1 byte)
    ; [rsp + 25] = saturation (1 byte)
    ; [rsp + 26] = value      (1 byte)
 


    ; r8 = r
    mov r8, rcx
    and r8, 0xFF0000
    shr r8, 16

    ; r9 = g
    mov r9, rcx
    and r9, 0x00FF00
    shr r9, 8
 
    ; r10 = b
    mov r10, rcx
    and r10, 0x0000FF



    ; [rsp] = cmax
    mov rax, r8
    cmp rax, r9
    cmovl rax, r9
    cmp rax, r10
    cmovl rax, r10
    mov [rsp], rax
 
    ; [rsp + 8] = cmin
    mov rax, r8
    cmp rax, r9
    cmovg rax, r9
    cmp rax, r10
    cmovg rax, r10
    mov [rsp + 8], rax

    ; [rsp + 16] = delta = cmax - cmin
    mov rax, [rsp]
    sub rax, [rsp + 8]
    mov [rsp + 16], rax  



    ; hue:

    mov rax, 0

    cmp qword [rsp + 16], 0
    je hsv_after_hue

    cmp r8, [rsp]
    je hsv_cmax_is_r

    cmp r9, [rsp]
    je hsv_cmax_is_g

    jmp hsv_cmax_is_b
    
hsv_cmax_is_r:
    ; xmm0 = (G' - B') / delta
    cvtsi2sd xmm0, r9
    cvtsi2sd xmm1, r10
    subsd xmm0, xmm1
    cvtsi2sd xmm1, [rsp + 16]  
    divsd xmm0, xmm1

    ; xmm1 = 6
    mov rax, 6
    cvtsi2sd xmm1, rax

    ; modulo (xmm0 % xmm1)
    movsd xmm2, xmm0
    divsd xmm2, xmm1        
    roundsd xmm3, xmm2, 3  
    mulsd xmm3, xmm1        
    subsd xmm0, xmm3

    ; correct the modulo if it is negative (add 6 if needed)
    xor rax, rax
    mov rbx, 6
    xorps xmm1, xmm1
    comisd xmm0, xmm1
    cmovb rax, rbx
    cvtsi2sd xmm1, rax
    addsd xmm0, xmm1

    ; adjust hue to range of 0 - 255
    mov rax, 255
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    mov rax, 6
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1

    ; move the hue to rax and jmp to the next block of code
    cvtsd2si rax, xmm0
    jmp hsv_after_hue

hsv_cmax_is_g: 
    ; xmm0 = (B' - R') / delta
    cvtsi2sd xmm0, r10
    cvtsi2sd xmm1, r8
    subsd xmm0, xmm1
    cvtsi2sd xmm1, [rsp + 16]  
    divsd xmm0, xmm1

    ; add 2
    mov rax, 2
    cvtsi2sd xmm1, rax
    addsd xmm0, xmm1

    ; adjust hue to range of 0 - 255
    mov rax, 255
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    mov rax, 6
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1

    ; move the hue to rax and jmp to the next block of code
    cvtsd2si rax, xmm0
    jmp hsv_after_hue

hsv_cmax_is_b:
    ; xmm0 = (R' - G') / delta
    cvtsi2sd xmm0, r8
    cvtsi2sd xmm1, r9
    subsd xmm0, xmm1
    cvtsi2sd xmm1, [rsp + 16]  
    divsd xmm0, xmm1

    ; add 4
    mov rax, 4
    cvtsi2sd xmm1, rax
    addsd xmm0, xmm1

    ; adjust hue to range of 0 - 255
    mov rax, 255
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1
    mov rax, 6
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1

    ; move the hue to rax and jmp to the next block of code
    cvtsd2si rax, xmm0
    jmp hsv_after_hue

hsv_after_hue:
    ; move the hue into the stack
    mov [rsp + 24], al



    ; saturation:

    mov rax, 0

    ; if cmax = 0, the saturation is 0
    cmp qword [rsp], 0 
    je hsv_after_saturation

hsv_cmax_is_not_zero:
    ; saturation = delta/cmax
    cvtsi2sd xmm0, [rsp + 16]
    cvtsi2sd xmm1, [rsp]
    divsd xmm0, xmm1

    ; adjust to be in range 0 - 255
    mov rax, 255
    cvtsi2sd xmm1, rax
    mulsd xmm0, xmm1

    cvtsd2si rax, xmm0

hsv_after_saturation:
    ; move the saturation into the stack
    mov [rsp + 25], al



    ; value:
    
    ; value = cmax
    mov rax, [rsp]
    mov [rsp + 26], al


    
    ; put the result (0xAAHHSSVV) into rax
    xor rax, rax

    ; put alpha into first slot
    mov rbx, rcx
    shr rbx, 24
    shl rbx, 24
    or rax, rbx

    ; put hue into second slot
    xor rbx, rbx
    mov bl, [rsp + 24]
    shl rbx, 16
    or rax, rbx

    ; put saturation into third slot
    xor rbx, rbx
    mov bl, [rsp + 25]
    shl rbx, 8
    or rax, rbx

    ; put value into fourth slot
    xor rbx, rbx
    mov bl, [rsp + 26]
    or rax, rbx



    ; reset the stack
    add rsp, 32

    ; restore registers
    pop r10
    pop r9
    pop r8
    pop rbx

    ; return
    ret




hsv_to_rgb:
    ; https://www.rapidtables.com/convert/color/hsv-to-rgb.html

    ; inputs:
    ; rcx = hsv color in form 0xFFHHSSVV

    ; store registers in stacks
    push rbx
    push r8
    push r9
    push r10

    sub rsp, 48
    ; [rsp]      = c (8 bytes, sd)
    ; [rsp + 8]  = x (8 bytes, sd)
    ; [rsp + 16] = m (8 bytes, sd)
    
    ; [rsp + 24] = red   (8 bytes, sd)
    ; [rsp + 32] = green (8 bytes, sd)
    ; [rsp + 40] = blue  (8 bytes, sd)



    ; r8 = h (adjust to range 0 - 360)
    mov r8, rcx
    and r8, 0xFF0000
    shr r8, 16
    cvtsi2sd xmm0, r8
    mov r8, 360
    cvtsi2sd xmm1, r8
    mulsd xmm0, xmm1
    mov r8, 255
    cvtsi2sd xmm1, r8
    divsd xmm0, xmm1
    cvtsd2si r8, xmm0

    ; r9 = s
    mov r9, rcx
    and r9, 0x00FF00
    shr r9, 8
 
    ; r10 = v
    mov r10, rcx
    and r10, 0x0000FF



    ; [rsp] = c = saturation * value
    cvtsi2sd xmm0, r9
    cvtsi2sd xmm1, r10
    mulsd xmm0, xmm1
    mov rax, 255 * 255
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1  
    movq [rsp], xmm0



    ; [rsp + 8] = x = c * (1 - abs((hue / 60) % 2 - 1))

    ; xmm0 = hue / 60
    mov rax, r8
    cvtsi2sd xmm0, rax
    mov rax, 60
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1

    ; xmm1 = 2
    mov rax, 2
    cvtsi2sd xmm1, rax

    ; modulo (xmm0 % xmm1)
    movsd xmm2, xmm0
    divsd xmm2, xmm1        
    roundsd xmm3, xmm2, 3  
    mulsd xmm3, xmm1        
    subsd xmm0, xmm3

    ; subtract 1
    mov rax, 1
    cvtsi2sd xmm1, rax
    subsd xmm0, xmm1    
 
    ; get the absolute value
    movsd xmm1, [abs_mask_sd]
    andpd xmm0, xmm1 

    ; xmm1 = 1 - xmm0
    mov rax, 1
    cvtsi2sd xmm1, rax
    subsd xmm1, xmm0

    ; xmm0 = xmm1 * c = x
    movsd xmm0, [rsp]
    mulsd xmm0, xmm1

    ; move x into [rsp + 8]
    movq [rsp + 8], xmm0



    ; [rsp + 16] = m = value - c
    cvtsi2sd xmm0, r10
    mov rax, 255
    cvtsi2sd xmm1, rax
    divsd xmm0, xmm1
    movsd xmm1, [rsp]
    subsd xmm0, xmm1
    movq [rsp + 16], xmm0



    ; determine which case this color falls under to determine the rgb
    cmp r8, 60
    jl hsv_to_rgb_case_one

    cmp r8, 120
    jl hsv_to_rgb_case_two

    cmp r8, 180
    jl hsv_to_rgb_case_three
   
    cmp r8, 240
    jl hsv_to_rgb_case_four

    cmp r8, 300
    jl hsv_to_rgb_case_five

    jmp hsv_to_rgb_case_six

hsv_to_rgb_case_one:
    ; if 0 <= h < 60, (c, x, 0)

    ; c
    movsd xmm0, [rsp]
    movq [rsp + 24], xmm0
    
    ; x
    movsd xmm0, [rsp + 8]
    movq [rsp + 32], xmm0

    ; 0
    xorps xmm0, xmm0
    movq [rsp + 40], xmm0

    jmp hsv_to_rgb_after_cases

hsv_to_rgb_case_two:
    ; if 60 <= h < 120, (x, c, 0)

    ; x
    movsd xmm0, [rsp + 8]
    movq [rsp + 24], xmm0
    
    ; c
    movsd xmm0, [rsp]
    movq [rsp + 32], xmm0

    ; 0
    xorps xmm0, xmm0
    movq [rsp + 40], xmm0

    jmp hsv_to_rgb_after_cases

hsv_to_rgb_case_three:
    ; if 120 <= h < 180, (0, c, x)

    ; 0
    xorps xmm0, xmm0
    movq [rsp + 24], xmm0
    
    ; c
    movsd xmm0, [rsp]
    movq [rsp + 32], xmm0

    ; x
    movsd xmm0, [rsp + 8]
    movq [rsp + 40], xmm0

    jmp hsv_to_rgb_after_cases

hsv_to_rgb_case_four:
    ; if 180 <= h < 240, (0, x, c)

    ; 0
    xorps xmm0, xmm0
    movq [rsp + 24], xmm0
    
    ; x
    movsd xmm0, [rsp + 8]
    movq [rsp + 32], xmm0

    ; c
    movsd xmm0, [rsp]
    movq [rsp + 40], xmm0

    jmp hsv_to_rgb_after_cases

hsv_to_rgb_case_five:
    ; if 240 <= h < 300, (x, 0, c)

    ; x
    movsd xmm0, [rsp + 8]
    movq [rsp + 24], xmm0
    
    ; 0
    xorps xmm0, xmm0
    movq [rsp + 32], xmm0

    ; c
    movsd xmm0, [rsp]
    movq [rsp + 40], xmm0

    jmp hsv_to_rgb_after_cases

hsv_to_rgb_case_six:
    ; if 300 <= h < 360, (c, 0, x)

    ; c
    movsd xmm0, [rsp]
    movq [rsp + 24], xmm0
    
    ; 0
    xorps xmm0, xmm0
    movq [rsp + 32], xmm0

    ; x
    movsd xmm0, [rsp + 8]
    movq [rsp + 40], xmm0

hsv_to_rgb_after_cases:



    ; put the result (0xAAHHSSVV) into rax
    xor rax, rax

    ; put alpha into first slot
    mov rbx, rcx
    shr rbx, 24
    shl rbx, 24
    or rax, rbx

    ; now for r,g,b, add m and multiply to get the final values before putting them into the slots:

    ; put red into second slot
    movsd xmm0, [rsp + 24]
    movsd xmm1, [rsp + 16]
    addsd xmm0, xmm1
    mov rbx, 255
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    cvtsd2si rbx, xmm0
    shl rbx, 16
    or rax, rbx

    ; put green into second slot
    movsd xmm0, [rsp + 32]
    movsd xmm1, [rsp + 16]
    addsd xmm0, xmm1
    mov rbx, 255
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    cvtsd2si rbx, xmm0
    shl rbx, 8
    or rax, rbx

    ; put blue into second slot
    movsd xmm0, [rsp + 40]
    movsd xmm1, [rsp + 16]
    addsd xmm0, xmm1
    mov rbx, 255
    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    cvtsd2si rbx, xmm0
    or rax, rbx



    ; reset stack
    add rsp, 48

    ; restore registers
    pop r10
    pop r9 
    pop r8
    pop rbx
    
    ; return
    ret





; Window functions:

get_time:
    push rax
    push rcx
    sub rsp, 32
    lea rcx, [rel TIMER_CURR]
    call QueryPerformanceCounter
    mov rax, [rel TIMER_CURR]
    sub rax, [rel TIMER_START]
    cvtsi2sd xmm1, rax
    movsd xmm0, [rel TIMER_FREQ]
    mulsd xmm0, xmm1
    add rsp, 32
    pop rcx
    pop rax
    ret



; Drawing functions:

draw_pixel:
    ; inputs:
    ; rcx = color (in form 0xAARRGGBB)
    ; rdx = x
    ; r8 = y

    ; store registers in the stack
    push rax
    push r9

    ; rdi = ptr to pixel to draw to
    mov rdi, [PIXELS]
    mov rax, r8
    imul rax, SCREEN_WIDTH
    add rax, rdx
    shl rax, 2
    add rdi, rax

    ; clear out r9 to prepare to move bytes into it
    xor r9, r9

    ; xmm2 = alpha
    ; xmm3 = 255
    mov r9, rcx
    shr r9, 24
    cvtsi2sd xmm2, r9
    mov r9b, 0xFF        
    cvtsi2sd xmm3, r9

    ; clear rax to prepare to add the r, g, and b to it
    xor rax, rax

    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov r9, rcx
    and r9, 0xFF0000
    shr r9, 16
    cvtsi2sd xmm0, r9
    mov r9b, [rdi + 2]  
    cvtsi2sd xmm1, r9

    ; calculate the new r and move it into r9
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor r9, r9
    cvttsd2si r9, xmm0

    ; add the r value to rax
    shl r9, 16
    or rax, r9

    ; g:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov r9, rcx
    and r9, 0x00FF00
    shr r9, 8
    cvtsi2sd xmm0, r9
    mov r9b, [rdi + 2]  
    cvtsi2sd xmm1, r9

    ; calculate the new g and move it into r9
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor r9, r9
    cvttsd2si r9, xmm0

    ; add the g value to rax
    shl r9, 8
    or rax, r9

    ; b:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov r9, rcx
    and r9, 0xFF
    cvtsi2sd xmm0, r9
    mov r9b, [rdi + 2]  
    cvtsi2sd xmm1, r9

    ; calculate the new b and move it into r9
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor r9, r9
    cvttsd2si r9, xmm0

    ; add the b value to rax
    or rax, r9

    ; draw the pixel
    stosd

    ; restore registers and return
    pop r9
    pop rax
    ret




draw_horizontal_line:
    ; inputs:
    ; rcx = color (in form 0xAARRGGBB)
    ; rdx = left x (line is drawn to right of this x position)
    ; r8 = y
    ; r9 = width

    ; store registers in the stack
    push rdx

    ; reserve stack space and start the iterator 0
    sub rsp, 8
    mov qword [rsp], 0

    ; don't draw anything if the line is off the screen
    cmp rdx, SCREEN_WIDTH
    jge end_draw_horizontal_line
    cmp r8, SCREEN_HEIGHT
    jge end_draw_horizontal_line

draw_horizontal_line_loop:
    ; end the loop if the next pixel goes off the screen
    cmp rdx, SCREEN_WIDTH
    jge end_draw_horizontal_line

    ; end the loop if the entire width has been drawn
    cmp qword [rsp], r9
    jge end_draw_horizontal_line

    ; draw a single pixel
    call draw_pixel
   
    ; add 1 to the x pos, increment the iterator, and repeat the loop
    add rdx, 1
    add qword [rsp], 1
    jmp draw_horizontal_line_loop

end_draw_horizontal_line:
    ; reset the stack, reset rdx, and return
    add rsp, 8
    pop rdx
    ret



draw_rect:
    ; inputs:
    ; rcx = color (in form 0xAARRGGBB)
    ; rdx = left x (rect is drawn to right of this point)
    ; r8 = bottom y (rect is drawn upward from this point)
    ; r9 = width
    ; r10 = height

    ; store r8 in the stack
    push r8

    ; restore stack space and start the iterator at 0
    sub rsp, 8
    mov qword [rsp], 0

    ; don't draw anything if the rect is off the screen
    cmp rdx, SCREEN_WIDTH
    jge end_draw_rect
    cmp r8, SCREEN_HEIGHT
    jge end_draw_rect

draw_rect_loop:
    ; end the loop if the next pixel goes off the screen
    cmp r8, SCREEN_HEIGHT
    jge end_draw_rect

    ; end the loop if the entire height has been drawn
    cmp qword [rsp], r10
    jge end_draw_rect

    ; draw a single horizontal line
    call draw_horizontal_line
   
    ; add 1 to the y pos, increment the iterator, and repeat the loop
    add r8, 1
    add qword [rsp], 1
    jmp draw_rect_loop

end_draw_rect:
    ; reset the stack, reset r8, and return
    add rsp, 8
    pop r8
    ret



fill_screen:
    ; inputs:
    ; rcx = color (in form 0xAARRGGBB)

    ; store registers in the stack
    push rdx
    push r8
    push r9
    push r10

    ; load in the inputs and draw a rectangle over the whole screen
    mov rdx, 0
    mov r8, 0
    mov r9, SCREEN_WIDTH
    mov r10, SCREEN_HEIGHT
    call draw_rect

    ; restore the registers and return
    pop r10
    pop r9
    pop r8
    pop rdx
    ret



draw_shader:
    ; inputs:
    ; rcx = pixel function
    ; rdx = pos and size

    ; store rbx in the stack and reserve stack space
    push rbx
    sub rsp, 24

    ; calculate the amount of pixels that needs to be drawn every horizontal line (the gradient may be cut off by the end of the screen)
    mov rbx, [rdx + x_pos]
    add rbx, [rdx + width]
    mov [rsp], rbx

    ; if r15 is less than or equal to 0, none of the drawing is cut off
    cmp ebx, dword SCREEN_WIDTH
    jle draw_shader_none_cut_off

    ; if r15 is greater than 0, some of the gradient is cut off and this has to be accounted for
    mov rbx, SCREEN_WIDTH
    sub rbx, [rdx + x_pos]
    mov [rsp], rbx
    jmp draw_shader_calculate_start_y

draw_shader_none_cut_off:
    mov rbx, [rdx + width]
    mov [rsp], rbx  

draw_shader_calculate_start_y:   
    mov qword [rsp + 8], 0

    cmp qword [rdx + y_pos], 0
    jge draw_shader_loop_y

    xor rbx, rbx
    sub rbx, [rdx + y_pos]
    mov [rsp + 8], rbx

    jmp draw_shader_end
    
draw_shader_loop_y:
    ; load the start of the pixels array into rdi
    mov rdi, [rel PIXELS]

    ; rbx = start row + current row + 28 (buffer)
    mov rbx, 28
    add rbx, [rdx + y_pos]
    add rbx, [rsp + 8]

    ; if the row is above the screen, stop drawing
    cmp rbx, WINDOW_HEIGHT
    jge draw_shader_end

    ; rbx = rbx * screen_width + column 
    ; rbx *= 4 (there are 4 bytes per pixel)
    imul rbx, SCREEN_WIDTH
    add rbx, [rdx + x_pos]
    shl rbx, 2

    ; add the offset to rdi
    add rdi, rbx

    ; exit loop if y >= height
    mov rbx, [rdx + height]
    cmp [rsp + 8], rbx
    jge draw_shader_end    

    ; x = 0 (start at first column)
    mov qword [rsp + 16], 0
    cmp qword [rdx + x_pos], 0
    jge draw_shader_loop_x

    mov rbx, 0
    sub rbx, [rdx + x_pos]
    mov [rsp + 16], rbx
    
    mov rbx, [rsp + 16]
    shl rbx, 2
    add rdi, rbx

draw_shader_loop_x:
    ; Move to next row if x >= width
    mov rbx, [rsp]
    cmp [rsp + 16], rbx
    jge draw_shader_next_row     

    ; make room in the stack for the uv coordinates (2 sd numbers)
    sub rsp, 16
    
    ; move uv.x into [rsp]
    mov rbx, [rsp + 32]
    cvtsi2sd xmm0, rbx
    mov rbx, [rdx + width]
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1
    movsd [rsp], xmm0

    mov rbx, [rsp + 32]
    cmp rbx, 0
    jnz draw_shader_loop_x_x_is_not_zero
 
    ; if x == 0, set uv.x to a very small, nonzero number to eliminate certain arithmetic issues
    xorps xmm0, xmm0
    mov rbx, 1
    cvtsi2sd xmm0, rbx
    mov rbx, 10000
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1
    movsd [rsp], xmm0
   
draw_shader_loop_x_x_is_not_zero:
    ; move uv.y into [rsp + 8]
    mov rbx, [rsp + 24]
    cvtsi2sd xmm0, rbx
    mov rbx, [rdx + height]
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1
    movq rbx, xmm0
    mov [rsp + 8], rbx

    mov rbx, [rsp + 24]
    cmp rbx, 0
    jnz draw_shader_loop_x_y_is_not_zero

    ; if y == 0, set uv.y to a very small, nonzero number to eliminate certain arithmetic issues
    xorps xmm0, xmm0
    mov rbx, 1
    cvtsi2sd xmm0, rbx
    mov rbx, 10000
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1
    movsd [rsp + 8], xmm0

draw_shader_loop_x_y_is_not_zero:
    ; call the pixel function (this is where the normal shader code is)
    jmp rcx

after_pixel_function:
    ; reset the stack
    add rsp, 16

    ; add the new pixel into the pixels array
    stosd

    ; increment x and repeat the loop
    mov rbx, [rsp + 16]
    inc rbx
    mov [rsp + 16], rbx
    jmp draw_shader_loop_x
    
draw_shader_next_row:
    ; increment y and start a new row
    mov rbx, [rsp + 8]
    inc rbx
    mov [rsp + 8], rbx
    jmp draw_shader_loop_y

draw_shader_end:
    ; reset the stack, reset rbx, and return
    add rsp, 24
    pop rbx
    ret
    


; Shader pixel functions:

stripes_pixel_function:
    ; https://www.shadertoy.com/view/lcKyWG

    ; inputs:
    ; r8 = ptr to stripes_data

    ; rbx can be used for the math
    ; rax must return the color for the pixel



    xor rbx, rbx
    mov bl, [r8 + stripes_horizontal]
    cmp rbx, 0
    je vertical_stripes

    ; draw horizontal stripes (using uv.x instead of uv.y)
    movsd xmm0, [rsp + 8]
    jmp after_vertical_stripes
    
vertical_stripes:
    ; draw vertical stripes (using uv.y instead of uv.x)
    movsd xmm0, [rsp]

after_vertical_stripes:
    xor rbx, rbx
    mov bl, [r8 + stripe_num]

    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1

    mov rbx, 2
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1

    mov rbx, 1
    cvtsi2sd xmm1, rbx

    movsd xmm2, xmm0
    divsd xmm2, xmm1        
    roundsd xmm3, xmm2, 3  
    mulsd xmm3, xmm1        
    subsd xmm0, xmm3

    ; xmm1 = 1/2
    mov rbx, 2
    cvtsi2sd xmm2, rbx
    divsd xmm1, xmm2

    xor rax, rax

    comisd xmm0, xmm1
    jb stripes_less_than

    ; move the alpha and the 255 into the xmm registers
    ; note: 0xFF = 255
    mov bl, byte [r8 + stripe_color2 + 3]
    cvtsi2sd xmm2, rbx
    mov bl, 0xFF        
    cvtsi2sd xmm3, rbx

    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + stripe_color2 + 2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the r component
    shl rbx, 16
    or rax, rbx

    ; g:
    ; move the new and original g values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + stripe_color2 + 1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the g component
    shl rbx, 8
    or rax, rbx

    ; b:
    ; move the new and original b values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + stripe_color2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the b component
    or rax, rbx

    jmp after_pixel_function

stripes_less_than:
    ; move the alpha and the 255 into the xmm registers
    ; note: 0xFF = 255
    mov bl, byte [r8 + stripe_color1 + 3]
    cvtsi2sd xmm2, rbx
    mov bl, 0xFF        
    cvtsi2sd xmm3, rbx

    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + stripe_color1 + 2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the r component
    shl rbx, 16
    or rax, rbx

    ; g:
    ; move the new and original g values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + stripe_color1 + 1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the g component
    shl rbx, 8
    or rax, rbx

    ; b:
    ; move the new and original b values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + stripe_color1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the b component
    or rax, rbx

    jmp after_pixel_function
    




checkers_pixel_function:
    ; https://www.shadertoy.com/view/McKyWG

    ; inputs:
    ; r8 = ptr to checkers_data

    ; rbx can be used for the math
    ; rax must return the color for the pixel



    movsd xmm0, [rsp]
    movsd xmm4, [rsp + 8]

    xor rbx, rbx
    mov bl, [r8 + checker_num]

    cvtsi2sd xmm1, rbx
    mulsd xmm0, xmm1
    mulsd xmm4, xmm1

    mov rbx, 2
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1
    divsd xmm4, xmm1

    mov rbx, 1
    cvtsi2sd xmm1, rbx

    movsd xmm2, xmm0        
    roundsd xmm3, xmm2, 3         
    subsd xmm0, xmm3

    movsd xmm2, xmm4
    roundsd xmm3, xmm2, 3
    subsd xmm4, xmm3

    ; xmm1 = 1/2
    mov rbx, 2
    cvtsi2sd xmm2, rbx
    divsd xmm1, xmm2

    xor rax, rax

    comisd xmm0, xmm1
    jb checkers_first_below

    comisd xmm4, xmm1
    jb checkers_color1

    jmp checkers_color2

checkers_first_below:
    comisd xmm4, xmm1
    jb checkers_color2
 
    jmp checkers_color1

checkers_color2:
    ; move the alpha and the 255 into the xmm registers
    ; note: 0xFF = 255
    mov bl, byte [r8 + checker_color2 + 3]
    cvtsi2sd xmm2, rbx
    mov bl, 0xFF        
    cvtsi2sd xmm3, rbx

    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + checker_color2 + 2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the r component
    shl rbx, 16
    or rax, rbx

    ; g:
    ; move the new and original g values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + checker_color2 + 1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the g component
    shl rbx, 8
    or rax, rbx

    ; b:
    ; move the new and original b values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + checker_color2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the b component
    or rax, rbx

    jmp checkers_keep_going

checkers_color1:
    ; move the alpha and the 255 into the xmm registers
    ; note: 0xFF = 255
    mov bl, byte [r8 + checker_color1 + 3]
    cvtsi2sd xmm2, rbx
    mov bl, 0xFF        
    cvtsi2sd xmm3, rbx

    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + checker_color1 + 2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the r component
    shl rbx, 16
    or rax, rbx

    ; g:
    ; move the new and original g values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + checker_color1 + 1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the g component
    shl rbx, 8
    or rax, rbx

    ; b:
    ; move the new and original b values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + checker_color1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the b component
    or rax, rbx
    
checkers_keep_going:
    jmp after_pixel_function





circle_pixel_function:
    ; inputs:
    ; r8 = ptr to circle_data

    ; rbx can be used for the math
    ; rax must return the color for the pixel



    ; xmm0 = 1/2
    mov rbx, 1
    cvtsi2sd xmm0, rbx
    mov rbx, 2
    cvtsi2sd xmm1, rbx
    divsd xmm0, xmm1

    ; xmm1 = (uv.x - 0.5) ^ 2
    movsd xmm1, [rsp]   
    subsd xmm1, xmm0
    mulsd xmm1, xmm1

    ; xmm2 = (uv.y - 0.5) ^ 2
    movsd xmm2, [rsp + 8]
    subsd xmm2, xmm0
    mulsd xmm2, xmm2

    ; xmm1 = distance squared = (uv.x-0.5)^2 + (uv.y-0.5)^2
    addsd xmm1, xmm2

    ; xmm0 = 1/4
    mov rbx, 1
    cvtsi2sd xmm0, rbx
    mov rbx, 4
    cvtsi2sd xmm2, rbx
    divsd xmm0, xmm2

    ; if the distance is greater than 0.25, the pixel is out of the range of the circle
    comisd xmm1, xmm0
    jb pixel_on_circle

    ; this pixel is not part of the so just redraw whatever color is already there then return
    mov rax, [rdi]
    jmp after_pixel_function

pixel_on_circle:
    xor rax, rax

    ; move the alpha and the 255 into the xmm registers
    ; note: 0xFF = 255
    mov bl, byte [r8 + circle_color + 3]
    cvtsi2sd xmm2, rbx
    mov bl, 0xFF        
    cvtsi2sd xmm3, rbx

    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + circle_color + 2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the r component
    shl rbx, 16
    or rax, rbx

    ; g:
    ; move the new and original g values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + circle_color + 1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the g component
    shl rbx, 8
    or rax, rbx

    ; b:
    ; move the new and original b values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + circle_color]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the b component
    or rax, rbx
 
    ; return
    jmp after_pixel_function



squircle_pixel_function:
    ; https://www.shadertoy.com/view/4c3fR7

    ; inputs:
    ; r8 = ptr to squircle_data

    ; rbx can be used for the math
    ; rax must return the color for the pixel



    ; xmm0 = uv.x
    ; xmm1 = uv.y
    movsd xmm0, [rsp]
    movsd xmm1, [rsp + 8]

    ; xmm0 = uv.x * 2
    ; xmm1 = uv.y * 2
    mov rbx, 2
    cvtsi2sd xmm2, rbx
    mulsd xmm0, xmm2
    mulsd xmm1, xmm2
 
    ; xmm0 = uv.x * 2 - 1
    ; xmm1 = uv.y * 2 - 1
    mov rbx, 1
    cvtsi2sd xmm2, rbx
    subsd xmm0, xmm2
    subsd xmm1, xmm2

    ; xmm0 = abs(uv.x * 2 - 1)
    ; xmm1 = abs(uv.y * 2 - 1)
    movq xmm2, qword [abs_mask_sd]
    andpd xmm0, xmm2
    andpd xmm1, xmm2

    ; reserve stack space
    sub rsp, 24

    ; move rcx, rdx, and uv.y to stack
    mov [rsp], rcx
    mov [rsp + 8], rdx
    movsd [rsp + 16], xmm1

    movsd xmm2, [r8 + squircle_corner_amount]
    movq rcx, xmm0
    movq rdx, xmm2
    call calculate_x_to_power_y

    movsd xmm0, [rsp + 16]
    movq rcx, xmm0
    movsd xmm2, [r8 + squircle_corner_amount]
    movq rdx, xmm2

    ; move the result to stack
    movq xmm0, rax
    movsd [rsp + 16], xmm0

    call calculate_x_to_power_y
   
    ; xmm0 = dist
    movq xmm0, rax
    movsd xmm1, [rsp + 16]
    addsd xmm0, xmm1

    ; reset rcx and rdx
    mov rcx, [rsp]
    mov rdx, [rsp + 8]

    ; reset the stack
    add rsp, 24

    ; if the distance is greater than 1.0, the pixel is out of the range of the squircle
    mov rax, 1
    cvtsi2sd xmm1, rax
    comisd xmm0, xmm1
    jb pixel_on_squircle

    ; this pixel is not part of the so just redraw whatever color is already there then return
    mov rax, [rdi]
    jmp after_pixel_function

pixel_on_squircle:
    xor rax, rax

    ; move the alpha and the 255 into the xmm registers
    ; note: 0xFF = 255
    mov bl, byte [r8 + squircle_color + 3]
    cvtsi2sd xmm2, rbx
    mov bl, 0xFF        
    cvtsi2sd xmm3, rbx

    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + squircle_color + 2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the r component
    shl rbx, 16
    or rax, rbx

    ; g:
    ; move the new and original g values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + squircle_color + 1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the g component
    shl rbx, 8
    or rax, rbx

    ; b:
    ; move the new and original b values into the xmm0 and xmm1 registers
    mov bl, byte [r8 + squircle_color]
    cvtsi2sd xmm0, rbx
    mov bl, byte [rdi]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0
    
    ; set the b component
    or rax, rbx

    ; return
    jmp after_pixel_function
    



image_pixel_function:
    ; inputs:
    ; r8 = ptr to image_drawing_data

    ; rbx can be used for the math
    ; rax must return the color for the pixel



    ; xmm0 = y (0-1)
    ; xmm3 = x (0-1)
    movsd xmm0, [rsp + 8]
    movsd xmm3, [rsp]

    ; store r9 and r10 in the stack
    push r9
    push r10

    ; r10 = ptr to image data
    mov r10, [r8 + image_to_draw_ptr]

    mov r9d, dword [r10 + image_width]  ; r9 = width

    cvtsi2sd xmm1, [r10 + image_height]
    mov rbx, 1
    cvtsi2sd xmm2, rbx
    subsd xmm1, xmm2
    mulsd xmm0, xmm1

    cmp byte [r8 + image_flip_y], 0 
    je image_pixel_function_after_flip_y

image_pixel_function_flip_y:
    ; select the pixel from the opposite side of the image, thus swapping it
    subsd xmm1, xmm0
    movsd xmm0, xmm1

image_pixel_function_after_flip_y:
    cvtsd2si rbx, xmm0
    imul r9, rbx                        ; r9 = y * width
 
    movsd xmm0, xmm3
    cvtsi2sd xmm1, [r10 + image_width]
    mov rbx, 1
    cvtsi2sd xmm2, rbx
    subsd xmm1, xmm2
    mulsd xmm0, xmm1

    cmp byte [r8 + image_flip_x], 0
    je image_pixel_function_after_flip_x

image_pixel_function_flip_x:
    ; select the pixel from the opposite side of the image, thus swapping it
    subsd xmm1, xmm0
    movsd xmm0, xmm1

image_pixel_function_after_flip_x:
    cvtsd2si rbx, xmm0
    add r9, rbx                         ; r9 = y * width + x
    imul r9, 4                          ; r9 = (y * width + x) * channels 
    add r9, [r10 + pixel_data]          ; r9 = data + offset

    ; clear registers to move colors values into them
    xor rax, rax
    xor rbx, rbx



    ; r:
    xor rbx, rbx
    mov bl, [r9]

    cmp word [r8 + image_r_shift], 0
    jge image_pixel_function_positive_r

image_pixel_function_negative_r:
    ; if r - r_shift will be less than 0, simply set r to r_shift so the resulting calculation will be 0, not a negative number
    xor r10, r10
    sub r10w, [r8 + image_r_shift]
    cmp rbx, r10
    cmovl rbx, r10

    ; add the image_r_shift to rbx 
    add bx, [r8 + image_r_shift]

    jmp image_pixel_function_after_move_r

image_pixel_function_positive_r:
    ; add the image_r_shift to rbx 
    add bx, [r8 + image_r_shift]
    mov r10, 255
    cmp rbx, 255
    cmovg rbx, r10

image_pixel_function_after_move_r:
    shl rbx, 16
    or rax, rbx

    ; g:
    xor rbx, rbx
    mov bl, [r9 + 1]

    cmp word [r8 + image_g_shift], 0
    jge image_pixel_function_positive_g

image_pixel_function_negative_g:
    ; if g - g_shift will be less than 0, simply set g to g_shift so the resulting calculation will be 0, not a negative number
    xor r10, r10
    sub r10w, [r8 + image_g_shift]
    cmp rbx, r10
    cmovl rbx, r10

    ; add the image_g_shift to rbx
    add bx, [r8 + image_g_shift]

    jmp image_pixel_function_after_move_g

image_pixel_function_positive_g:
    ; add the image_g_shift to rbx
    add bx, [r8 + image_g_shift]
    mov r10, 255
    cmp rbx, 255
    cmovg rbx, r10

image_pixel_function_after_move_g:
    shl rbx, 8
    or rax, rbx

    ; b:
    xor rbx, rbx
    mov bl, [r9 + 2]

    cmp word [r8 + image_b_shift], 0
    jge image_pixel_function_positive_b

image_pixel_function_negative_b:
    ; if b - b_shift will be less than 0, simply set b to b_shift so the resulting calculation will be 0, not a negative number
    xor r10, r10
    sub r10w, [r8 + image_b_shift]
    cmp rbx, r10
    cmovl rbx, r10

    ; add the image_b_shift to rbx
    add bx, [r8 + image_b_shift]

    jmp image_pixel_function_after_move_b

image_pixel_function_positive_b:
    ; add the image_b_shift to rbx
    add bx, [r8 + image_b_shift]
    mov r10, 255
    cmp rbx, 255
    cmovg rbx, r10

image_pixel_function_after_move_b:
    ; set the b component
    or rax, rbx



    ; store rcx in the stack
    push rcx

    ; convert color from rgb to hsv (it is now in rax)
    mov rcx, rax
    call rgb_to_hsv

    ; clear rcx to prepare to move the new hsv values into it
    xor rcx, rcx    



    ; hue

    ; rbx = hue byte
    mov rbx, rax
    and rbx, 0xFF0000
    shr rbx, 16

    ; check if the image_h_shift is positive or negative
    cmp word [r8 + image_h_shift], 0
    jge image_pixel_function_positive_h

image_pixel_function_negative_h:
    ; add the image_h_shift to rbx
    add bx, [r8 + image_h_shift]

    ; if h - h_shift will be less than 0, simply add 255 to h so the resulting calculation will be in the range 0 - 255, not a negative number
    xor r10, r10
    sub r10w, [r8 + image_h_shift]
    cmp rbx, r10
    mov r10, rbx
    add r10, 255
    cmovl rbx, r10

    ; add the image_h_shift to rbx
    add bx, [r8 + image_h_shift]

    jmp image_pixel_function_after_move_h

image_pixel_function_positive_h:
    ; add the image_h_shift to rbx 
    add bx, [r8 + image_h_shift]

    ; if the hue is greater than 255, subtract 255 to put it back in the range 0 - 255
    mov r10, rbx
    sub r10, 255
    cmp rbx, 255
    cmovg rbx, r10

image_pixel_function_after_move_h:
    ; move the hue into rcx
    shl rbx, 16
    or rcx, rbx



    ; saturation

    ; rbx = saturation byte
    mov rbx, rax
    and rbx, 0x00FF00
    shr rbx, 8

    ; check if the image_s_shift is positive or negative
    cmp word [r8 + image_s_shift], 0
    jge image_pixel_function_positive_s

image_pixel_function_negative_s:
    ; if s - s_shift will be less than 0, simply set s to s_shift so the resulting calculation will be 0, not a negative number
    xor r10, r10
    sub r10w, [r8 + image_s_shift]
    cmp rbx, r10
    cmovl rbx, r10

    ; add the image_s_shift to rbx
    add bx, [r8 + image_s_shift]

    jmp image_pixel_function_after_move_s

image_pixel_function_positive_s:
    ; add the image_s_shift to rbx 
    add bx, [r8 + image_s_shift]
    mov r10, 255
    cmp rbx, 255
    cmovg rbx, r10

image_pixel_function_after_move_s:
    ; move the saturation into rcx
    shl rbx, 8
    or rcx, rbx



    ; value

    ; rbx = value byte
    mov rbx, rax
    and rbx, 0x0000FF

    ; check if the image_v_shift is positive or negative
    cmp word [r8 + image_v_shift], 0
    jge image_pixel_function_positive_v

image_pixel_function_negative_v:
    ; if v - v_shift will be less than 0, simply set v to v_shift so the resulting calculation will be 0, not a negative number
    xor r10, r10
    sub r10w, [r8 + image_v_shift]
    cmp rbx, r10
    cmovl rbx, r10

    ; add the image_v_shift to rbx
    add bx, [r8 + image_v_shift]

    jmp image_pixel_function_after_move_v

image_pixel_function_positive_v:
    ; add the image_v_shift to rbx
    add bx, [r8 + image_v_shift]
    mov r10, 255
    cmp rbx, 255
    cmovg rbx, r10

image_pixel_function_after_move_v:
    ; move the value into rcx
    or rcx, rbx


  
    ; convert the hsv color back to rgb and restore rcx
    call hsv_to_rgb
    pop rcx

    ; move the rgb color into r10 and clear rax so the individual color channels can be extracted and added back to rax
    mov r10, rax
    xor rax, rax

    ; move the alpha and the 255 into the xmm registers (xmm2 and xmm3 respectively)
    ; note: 0xFF = 255
    mov bl, [r9 + 3]
    cvtsi2sd xmm2, rbx
    mov bl, 0xFF        
    cvtsi2sd xmm3, rbx

    ; multiply the alpha by the image's opacity
    mov bl, [r8 + image_opacity]
    cvtsi2sd xmm4, rbx
    divsd xmm4, xmm3
    mulsd xmm2, xmm4



    ; r:
    ; move the new and original r values into the xmm0 and xmm1 registers
    mov rbx, r10
    and rbx, 0xFF0000
    shr rbx, 16
    cvtsi2sd xmm0, rbx
    mov bl, [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvtsd2si rbx, xmm0

    ; add the r value to rax
    shl rbx, 16
    or rax, rbx



    ; g:
    ; move the new and original g values into the xmm0 and xmm1 registers
    mov rbx, r10
    and rbx, 0x00FF00
    shr rbx, 8
    cvtsi2sd xmm0, rbx
    mov bl, [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvtsd2si rbx, xmm0

    ; add the g value to rax
    shl rbx, 8
    or rax, rbx



    ; b:
    ; move the new and original b values into the xmm0 and xmm1 registers
    mov rbx, r10
    and rbx, 0x0000FF
    cvtsi2sd xmm0, rbx
    mov bl, [rdi]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm2
    divsd xmm0, xmm3
    addsd xmm0, xmm1
    xor rbx, rbx
    cvtsd2si rbx, xmm0

    ; add the b value to rax
    or rax, rbx


 
    ; reset r9 and r10 and return
    pop r9
    pop r10
    jmp after_pixel_function




gradient_pixel_function:
    ; https://www.shadertoy.com/view/lcKyWK

    ; inputs:
    ; r8 = ptr to gradient_data

    ; rbx can be used for the math
    ; rax must return the color for the pixel



    ; clear registers to prepare to move colors values into them
    xor rax, rax
    xor rbx, rbx



    ; alpha:

    ; xmm0 = c0 = uv.x * (top_right_color - top_left_color) + top_left_color
    mov bl, byte [r8 + gradient_top_right_color + 3]
    cvtsi2sd xmm0, rbx
    mov bl, byte [r8 + gradient_top_left_color + 3]
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    movsd xmm2, [rsp]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; xmm1 = c1 = uv.x * (btm_right_color - btm_left_color) + btm_left_color
    mov bl, byte [r8 + gradient_btm_right_color + 3]
    cvtsi2sd xmm1, rbx
    mov bl, byte [r8 + gradient_btm_left_color + 3]
    cvtsi2sd xmm2, rbx
    subsd xmm1, xmm2
    movsd xmm3, [rsp]
    mulsd xmm1, xmm3
    addsd xmm1, xmm2

    ; xmm0 = uv.y * (c0 - c1) + c1
    subsd xmm0, xmm1
    movsd xmm2, [rsp + 8]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; move the alpha and the 255 into the proper xmm registers (xmm4 and xmm5 respectively)
    ; note: 0xFF = 255
    movsd xmm4, xmm0
    mov bl, 0xFF        
    cvtsi2sd xmm5, rbx



    ; r:

    ; xmm0 = c0 = uv.x * (top_right_color - top_left_color) + top_left_color
    mov bl, byte [r8 + gradient_top_right_color + 2]
    cvtsi2sd xmm0, rbx
    mov bl, byte [r8 + gradient_top_left_color + 2]
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    movsd xmm2, [rsp]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; xmm1 = c1 = uv.x * (btm_right_color - btm_left_color) + btm_left_color
    mov bl, byte [r8 + gradient_btm_right_color + 2]
    cvtsi2sd xmm1, rbx
    mov bl, byte [r8 + gradient_btm_left_color + 2]
    cvtsi2sd xmm2, rbx
    subsd xmm1, xmm2
    movsd xmm3, [rsp]
    mulsd xmm1, xmm3
    addsd xmm1, xmm2

    ; xmm0 = uv.y * (c0 - c1) + c1
    subsd xmm0, xmm1
    movsd xmm2, [rsp + 8]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; xmm1 = current r value at the pixel
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new r and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm4
    divsd xmm0, xmm5
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0

    ; set the r component
    shl rbx, 16
    or rax, rbx



    ; g:

    ; xmm0 = c0 = uv.x * (top_right_color - top_left_color) + top_left_color
    mov bl, byte [r8 + gradient_top_right_color + 1]
    cvtsi2sd xmm0, rbx
    mov bl, byte [r8 + gradient_top_left_color + 1]
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    movsd xmm2, [rsp]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; xmm1 = c1 = uv.x * (btm_right_color - btm_left_color) + btm_left_color
    mov bl, byte [r8 + gradient_btm_right_color + 1]
    cvtsi2sd xmm1, rbx
    mov bl, byte [r8 + gradient_btm_left_color + 1]
    cvtsi2sd xmm2, rbx
    subsd xmm1, xmm2
    movsd xmm3, [rsp]
    mulsd xmm1, xmm3
    addsd xmm1, xmm2

    ; xmm0 = uv.y * (c0 - c1) + c1
    subsd xmm0, xmm1
    movsd xmm2, [rsp + 8]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; xmm1 = current g value at the pixel
    mov bl, byte [rdi + 1]  
    cvtsi2sd xmm1, rbx

    ; calculate the new g and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm4
    divsd xmm0, xmm5
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0

    ; set the g component
    shl rbx, 8
    or rax, rbx



    ; b:

    ; xmm0 = c0 = uv.x * (top_right_color - top_left_color) + top_left_color
    mov bl, byte [r8 + gradient_top_right_color]
    cvtsi2sd xmm0, rbx
    mov bl, byte [r8 + gradient_top_left_color]
    cvtsi2sd xmm1, rbx
    subsd xmm0, xmm1
    movsd xmm2, [rsp]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; xmm1 = c1 = uv.x * (btm_right_color - btm_left_color) + btm_left_color
    mov bl, byte [r8 + gradient_btm_right_color]
    cvtsi2sd xmm1, rbx
    mov bl, byte [r8 + gradient_btm_left_color]
    cvtsi2sd xmm2, rbx
    subsd xmm1, xmm2
    movsd xmm3, [rsp]
    mulsd xmm1, xmm3
    addsd xmm1, xmm2

    ; xmm0 = uv.y * (c0 - c1) + c1
    subsd xmm0, xmm1
    movsd xmm2, [rsp + 8]
    mulsd xmm0, xmm2
    addsd xmm0, xmm1

    ; xmm1 = current b value at the pixel
    mov bl, byte [rdi + 2]  
    cvtsi2sd xmm1, rbx

    ; calculate the new b and move it into rbx
    subsd xmm0, xmm1
    mulsd xmm0, xmm4
    divsd xmm0, xmm5
    addsd xmm0, xmm1
    xor rbx, rbx
    cvttsd2si rbx, xmm0

    ; set the b component
    or rax, rbx

    ; return
    jmp after_pixel_function




; Shader drawing functions (call these and they handle the draw_shader and shader_pixel_functions for you):

draw_stripes:
    ; inputs:
    ; rcx = ptr to stripe_data
    ; rdx = ptr to pos_and_size 

    push r8

    mov r8, rcx
    mov rcx, stripes_pixel_function
    call draw_shader

    pop r8
    ret

    
draw_checkers:
    ; inputs
    ; rcx = ptr to checker_data
    ; rdx = ptr to pos_and_size

    push r8

    mov r8, rcx
    mov rcx, checkers_pixel_function
    call draw_shader

    pop r8
    ret


draw_circle:
    ; inputs
    ; rcx = ptr to circle_data
    ; rdx = ptr to pos_and_size

    push r8
    
    mov r8, rcx
    mov rcx, circle_pixel_function
    call draw_shader

    pop r8
    ret


draw_squircle:
    ; inputs
    ; rcx = ptr to squircle_data
    ; rdx = ptr to pos_and_size

    push r8

    mov r8, rcx
    mov rcx, squircle_pixel_function
    call draw_shader
    
    pop r8
    ret


draw_image:
    ; inputs
    ; rcx = ptr to image_drawing_data
    ; rdx = ptr to pos_and_size

    push r8
    
    mov r8, rcx
    mov rcx, image_pixel_function
    call draw_shader

    pop r8
    ret


draw_gradient:
    ; inputs
    ; rcx = ptr to gradient_data
    ; rdx = ptr to pos_and_size

    push r8
    
    mov r8, rcx
    mov rcx, gradient_pixel_function
    call draw_shader

    pop r8
    ret



fill_screen_gradient:
    ; inputs:
    ; rcx = ptr to gradient_data

    ; store rdx in the stack and reserve stack space
    push rdx
    sub rsp, 32

    mov qword [rsp + x_pos], 0 
    mov qword [rsp + y_pos], 0 
    mov qword [rsp + width], SCREEN_WIDTH
    mov qword [rsp + height], SCREEN_HEIGHT

    ; load in the size_and_pos ptr and draw a gradient over the whole screen
    lea rdx, [rsp]
    call draw_gradient

    ; reset the stack, restore rdx, and return
    add rsp, 32
    pop rdx
    ret

    
