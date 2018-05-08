#![feature(lang_items)]
#![no_std]
//All used in vga_buffer
#![feature(const_fn)]
#![feature(unique)]
#![feature(ptr_internals)]

extern crate rlibc;
extern crate volatile;
extern crate spin;

//We use our VGA buffer module
#[macro_use]
mod vga_buffer;

//Ensures that rust_main() doesn't get renamed due to name mangling
#[no_mangle]
pub extern fn rust_main() {
    vga_buffer::clear_screen();
    println!("Hello!!!");
    loop{}
}


//This is our panic stuff which we need to implement
#[lang = "eh_personality"] #[no_mangle] pub extern fn eh_personality() {}
#[lang = "panic_fmt"] #[no_mangle] pub extern fn panic_fmt() -> ! {loop{}}
