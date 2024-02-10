use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::deflate::{DeflateEncoder, DeflateDecoder};
use compression::utils::slice::ByteArraySliceImpl;

#[test]
#[available_gas(1500000000)]
fn test_deflate() {
    let input = inputs::get_test_phrase_2();
    let compressed = DeflateEncoder::encode(input.slice(0, input.len()));
    let decompressed = DeflateDecoder::decode(compressed.slice(0, compressed.len()));

    assert(decompressed.unwrap() == inputs::get_test_phrase_2(), 'unexpected result')
}

