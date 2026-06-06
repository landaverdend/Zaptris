use godot::builtin::PackedByteArray;
use image::codecs::png::PngEncoder;
use image::ImageEncoder;
use qrcode::{Color, QrCode};

/// Encode `data` as a QR code and return raw PNG bytes.
/// Each module is 8×8 px with a 4-module quiet zone.
/// Returns an empty Vec on failure — safe to call from any thread.
pub fn generate_png(data: &str) -> Vec<u8> {
    let code = match QrCode::new(data.as_bytes()) {
        Ok(c)  => c,
        Err(e) => {
            eprintln!("[qr] encode error: {e}");
            return Vec::new();
        }
    };

    let scale   = 3usize;   // 2px per module — ~170px native for a typical invoice
    let quiet   = 3usize;
    let qr_size = code.width();
    let total   = (qr_size + quiet * 2) * scale;

    let mut pixels = vec![255u8; total * total];

    for row in 0..qr_size {
        for col in 0..qr_size {
            if code[(row, col)] == Color::Dark {
                let y0 = (row + quiet) * scale;
                let x0 = (col + quiet) * scale;
                for dy in 0..scale {
                    let row_start = (y0 + dy) * total;
                    for dx in 0..scale {
                        pixels[row_start + x0 + dx] = 0;
                    }
                }
            }
        }
    }

    let mut png_bytes: Vec<u8> = Vec::new();
    let encoder = PngEncoder::new(&mut png_bytes);
    if let Err(e) = encoder.write_image(&pixels, total as u32, total as u32, image::ColorType::L8) {
        eprintln!("[qr] PNG encode error: {e}");
        return Vec::new();
    }

    png_bytes
}

/// Convenience wrapper that returns a Godot PackedByteArray.
/// Only call this from the main thread.
pub fn generate_qr(data: &str) -> PackedByteArray {
    PackedByteArray::from(generate_png(data).as_slice())
}
