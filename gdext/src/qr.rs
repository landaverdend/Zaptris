use godot::builtin::PackedByteArray;
use image::codecs::png::PngEncoder;
use image::ImageEncoder;
use qrcode::QrCode;

pub fn generate_png(data: &str) -> Vec<u8> {
    let code = match QrCode::new(data.as_bytes()) {
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
