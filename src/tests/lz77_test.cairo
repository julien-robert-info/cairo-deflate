use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::lz77::{Lz77Encoder, Lz77Decoder};

#[test]
#[available_gas(30000000)]
fn test_lz77_cycle_1() {
    let compressed = Lz77Encoder::encode(inputs::get_test_phrase_1());
    let decompressed = Lz77Decoder::decode(compressed);

    assert(decompressed == inputs::get_test_phrase_1(), 'unexpected result')
}

#[test]
#[available_gas(300000000)]
fn test_lz77_cycle_2() {
    let compressed = Lz77Encoder::encode(inputs::get_test_phrase_2());
    let decompressed = Lz77Decoder::decode(compressed);

    assert(decompressed == inputs::get_test_phrase_2(), 'unexpected result')
}
