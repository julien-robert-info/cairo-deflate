use compression::commons::{Encoder, Decoder};
use compression::lz77::{Lz77Encoder, Lz77Decoder};

#[test]
#[available_gas(30000000)]
fn test_lz77_cycle_1() {
    let compressed = Lz77Encoder::encode(get_test_phrase_1());
    let decompressed = Lz77Decoder::decode(compressed);

    assert(decompressed == get_test_phrase_1(), 'unexpected result')
}

#[test]
#[available_gas(300000000)]
fn test_lz77_cycle_2() {
    let compressed = Lz77Encoder::encode(get_test_phrase_2());
    let decompressed = Lz77Decoder::decode(compressed);

    assert(decompressed == get_test_phrase_2(), 'unexpected result')
}

fn get_test_phrase_1() -> ByteArray {
    let mut test_phrase: ByteArray = Default::default();
    test_phrase.append_word('Blah blah blah blah blah!', 25);

    test_phrase
}

fn get_test_phrase_2() -> ByteArray {
    let mut test_phrase: ByteArray = Default::default();
    test_phrase.append_word('Four score and seven years ago ', 31);
    test_phrase.append_word('our fathers brought forth, on t', 31);
    test_phrase.append_word('his continent, a new nation, co', 31);
    test_phrase.append_word('nceived in Liberty, and dedicat', 31);
    test_phrase.append_word('ed to the proposition that all ', 31);
    test_phrase.append_word('men are created equal.', 22);

    test_phrase
}
