#![feature(lang_items)]
#![no_std]

extern crate rlibc;

//Ensures that rust_main() doesn't get renamed due to name mangling
#[no_mangle]
pub extern fn rust_main() {
    let hello = b"Hello World!";
    let color_byte = 0x1f;

    let mut hello_colored = [color_byte; 24];
    for (i, char_byte) in hello.into_iter().enumerate() {
        hello_colored[i*2] = *char_byte;
    }

    //Write 'Hello World!' to the center of the VGA buffer
    let buffer_ptr = (0xB8000 + 1988) as *mut _;
    unsafe {
        *buffer_ptr = hello_colored
    };
    loop{}
}

//This is our panic stuff which we need to implement
#[lang = "eh_personality"] #[no_mangle] pub extern fn eh_personality() {}
#[lang = "panic_fmt"] #[no_mangle] pub extern fn panic_fmt() -> ! {loop{}}
