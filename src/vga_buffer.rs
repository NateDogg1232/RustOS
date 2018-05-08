#![feature(unique)]
#![feature(const_fn)]
#![feature(ptr_internals)]


use core::ptr::Unique;
use core::fmt;
use volatile::Volatile;
use spin::Mutex;
#[allow(dead_code)]
#[derive(Debug, Clone, Copy)]
#[repr(u8)]
pub enum Color {
    Black,
    Blue,
    Green,
    Cyan,
    Red,
    Magenta,
    Brown,
    LightGrey,
    DarkGrey,
    LightBlue,
    LightGreen,
    LightCyan,
    LightRed,
    Pink,
    Yellow,
    White
}

//We can create a color code struct using the original Color enum
#[derive(Debug, Clone, Copy)]
struct ColorCode(u8);
impl ColorCode {
    //This is a helper function to help create a color function
    const fn new(foreground: Color, background: Color) -> ColorCode {
        return ColorCode((background as u8) << 4 | (foreground as u8));
    }
}

//This tag allows copy to be used with it
#[derive(Debug, Clone, Copy)]
//This tag is to make sure this struct is stored as a C struct, ensuring its order
#[repr(C)]
struct ScreenChar {
    ascii_character: u8,
    color_code: ColorCode
}

const BUFFER_HEIGHT: usize = 25;
const BUFFER_WIDTH: usize = 80;

struct Buffer {
    //Two dimensional array, with a type of a volatile ScreenChar.
     chars: [[Volatile<ScreenChar>; BUFFER_WIDTH]; BUFFER_HEIGHT],
}


pub struct Writer {
    column_position: usize,
    row_position: usize,
    color_code: ColorCode,
    buffer: Unique<Buffer>,
}

impl Writer {
    pub fn write_byte(&mut self, byte: u8) {
        match byte {
            b'\n' => self.new_line(),
            b'\0' => self.write_byte(b' '),
            byte => {
                if self.column_position >= BUFFER_WIDTH {
                    self.new_line();
                }

                let row = self.row_position;
                let col = self.column_position;

                let color_code = self.color_code;
                self.buffer().chars[row][col].write(ScreenChar {
                    ascii_character: byte,
                    color_code: color_code,
                });
                self.column_position += 1;
            }
        }
    }

    fn buffer(&mut self) -> &mut Buffer {
        unsafe { self.buffer.as_mut() }
    }


    fn new_line(&mut self) {
        self.row_position += 1;
        self.column_position = 0;
        if self.row_position >= BUFFER_HEIGHT {
            self.scroll_screen();
        }
    }

    fn scroll_screen(&mut self) {
        for row in 1..BUFFER_HEIGHT {
            for col in 0..BUFFER_WIDTH {
                let buffer = self.buffer();
                let character = buffer.chars[row][col].read();
                buffer.chars[row - 1][col].write(character);
            }
        }
        self.clear_row(BUFFER_HEIGHT - 1);
        self.column_position = 0;
        self.row_position = BUFFER_HEIGHT - 1;
    }

    fn clear_row(&mut self, row: usize) {
        let blank = ScreenChar {
            ascii_character: b' ',
            color_code: self.color_code
        };
        for col in 0..BUFFER_WIDTH {
            let buffer = self.buffer();
            buffer.chars[row][col].write(blank);
        }
    }
}


impl fmt::Write for Writer {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for byte in s.bytes() {
            self.write_byte(byte);
        }
        return Ok(());
    }
}


pub static WRITER: Mutex<Writer> = Mutex::new(Writer {
    column_position: 0,
    row_position: 0,
    color_code: ColorCode::new(Color::LightGreen, Color::Black),
    buffer: unsafe { Unique::new_unchecked(0xb8000 as *mut _) },
});


macro_rules! print {
    ($($arg:tt)*) => ({
        use core::fmt::Write;
        let mut writer = $crate::vga_buffer::WRITER.lock();
        writer.write_fmt(format_args!($($arg)*)).unwrap();
    });
}


macro_rules! println {
    ($fmt:expr) => (print!(concat!($fmt, "\n")));
    ($fmt:expr, $($arg:tt)*) => (print!(concat!($fmt, "\n"), $($arg)*));
}

pub fn clear_screen() {
    for _ in 0 .. BUFFER_HEIGHT {
        println!("");
    }
}
