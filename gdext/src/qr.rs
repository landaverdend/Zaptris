use godot::builtin::PackedByteArray;
use image::codecs::png::PngEncoder;
use image::ImageEncoder;
use qrcode::{EcLevel, QrCode};

pub fn generate_png(data: &str) -> Vec<u8> {
    // Low error correction trades resilience to scan damage for fewer
    // modules at a given display size — fine for a clean digital display,
    // not a printed/worn code. (We previously also uppercased the invoice
    // to force QR's Alphanumeric mode, which shrinks modules further — but
    // bech32 spec-allows uppercase, plenty of real wallet scanners
    // pattern-match the lowercase "lnbc" prefix before decoding and don't
    // recognize the uppercase form, so that part's reverted.)
    let code = match QrCode::with_error_correction_level(data.as_bytes(), EcLevel::L) {
        Ok(c)  => c,
        Err(e) => { eprintln!("[qr] encode error: {e}"); return Vec::new(); }
    };

    let img = code
        .render::<image::Luma<u8>>()
        .quiet_zone(true)
        .module_dimensions(9, 9)
        .build();

    let mut png_bytes: Vec<u8> = Vec::new();
    let encoder = PngEncoder::new(&mut png_bytes);
    if let Err(e) = encoder.write_image(
        img.as_raw(),
        img.width(),
        img.height(),
        image::ColorType::L8.into(),
    ) {
        eprintln!("[qr] PNG encode error: {e}");
        return Vec::new();
    }

    png_bytes
}

pub fn generate_qr(data: &str) -> PackedByteArray {
    PackedByteArray::from(generate_png(data).as_slice())
}
