// Prevents an additional console window on Windows in release builds
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    liferestart_desktop_lib::run()
}
