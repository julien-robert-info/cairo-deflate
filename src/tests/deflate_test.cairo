use compression::commons::{Encoder, Decoder};
use compression::deflate::{DeflateEncoder, DeflateDecoder};

// test phrase
// Lorem ipsum dolor sit amet, consectetur adipisicing elit. Tempore quod rem provident totam voluptates debitis eligendi a laborum quia odio itaque eos officiis suscipit, quidem, voluptatibus ipsum iure perferendis necessitatibus!

// DEFLATE
// PY9BjsMwDAO/wt6LvqTH/YBjM4WA2HIsqe+vgi16J4fDpy52yLToaHrogomjdPodVYexOj0WSpMpJlXGCzzEH/hjn1nGGdpwQebStzQOh6uXjrceMb04DY2buNjVfHE0QcFRNl05eoYUaBOFeDmDoBp033MqCxZWczhlMtfY7z+qbGFfb4nUmFw71wU3DFZa/vhP3T4=

#[test]
#[available_gas(4000000)]
fn test_deflate_compress() {
    let compressed = DeflateEncoder::encode(get_lorem());
    let expected = get_compressed_lorem();

    assert(compressed == expected, 'unexpected result')
}

// #[test]
// fn test_deflate_decompress() {
//     let mut input = get_compressed_lorem();

//     let decompressed = DeflateImpl::decompress(@input);
//     let expected = get_lorem();

//     assert(decompressed == expected, 'unexpected result')
// }

fn get_lorem() -> ByteArray {
    let mut lorem: ByteArray = Default::default();
    lorem.append_word('Lorem ipsum dolor sit amet, co', 30);
    lorem.append_word('nsectetur adipisicing elit. Te', 30);
    lorem.append_word('mpore quod rem provident totam', 30);
    lorem.append_word(' voluptates debitis eligendi a', 30);
    lorem.append_word(' laborum quia odio itaque eos ', 30);
    lorem.append_word('officiis suscipit, quidem, vol', 30);
    lorem.append_word('uptatibus ipsum iure perferend', 30);
    lorem.append_word('is necessitatibus!', 18);

    lorem
}

fn get_compressed_lorem() -> ByteArray {
    let mut lorem: ByteArray = Default::default();
    lorem.append_word('PY9BjsMwDAO/wt6LvqTH/YBjM4WA2H', 30);
    lorem.append_word('Isqe+vgi16J4fDpy52yLToaHrogomj', 30);
    lorem.append_word('dPodVYexOj0WSpMpJlXGCzzEH/hjn1', 30);
    lorem.append_word('nGGdpwQebStzQOh6uXjrceMb04DY2b', 30);
    lorem.append_word('uNjVfHE0QcFRNl05eoYUaBOFeDmDoB', 30);
    lorem.append_word('p033MqCxZWczhlMtfY7z+qbGFfb4nU', 30);
    lorem.append_word('mFw71wU3DFZa/vhP3T4=', 20);

    lorem
}
