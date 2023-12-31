use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::lz77::{Lz77Encoder, Lz77Decoder, Lz77Impl, Match};
use compression::offset_length_code::{ESCAPE_BYTE, OLCode};

#[test]
#[available_gas(450000)]
fn match_update() {
    let mut lz77 = Lz77Impl::new(@inputs::get_test_phrase_1());
    lz77.input_pos = 7;
    lz77.output_pos = 6;
    lz77.matches = array![Match { code: OLCode { length: 1, offset: 5 }, pos: 6 }];

    lz77.update_matches(lz77.input_read().unwrap());

    assert(lz77.matches.len() == 1, 'unexpected number of match 1');

    let mut matches = lz77.matches.span();
    let m = *matches.pop_front().unwrap();
    assert(m.code.length == 2, 'unexpected length 1');
    assert(m.code.offset == 5, 'unexpected offset 1');
    assert(m.pos == 7, 'unexpected pos 1');

    lz77.increment_pos();
    lz77.update_matches(lz77.input_read().unwrap());

    let mut matches = lz77.matches.span();
    let m = *matches.pop_front().unwrap();

    assert(m.code.length == 3, 'unexpected length 2');
    assert(m.code.offset == 5, 'unexpected offset 2');
    assert(m.pos == 8, 'unexpected pos 2');
}

#[test]
#[available_gas(450000)]
fn output_raw_code() {
    let mut lz77 = Lz77Impl::new(@inputs::get_test_phrase_1());
    lz77.input_pos = 7;

    lz77.output_raw_code(OLCode { length: 3, offset: 3 });

    let mut expected: ByteArray = Default::default();
    expected.append_word(' bl', 3);

    assert(lz77.output == expected, 'unexpected result');
}

#[test]
#[available_gas(900000)]
fn process_matches() {
    let mut lz77 = Lz77Impl::new(@inputs::get_test_phrase_1());
    lz77.input_pos = 13;
    lz77.output_pos = 6;
    lz77.matches = array![Match { code: OLCode { length: 3, offset: 5 }, pos: 10 }];

    lz77.process_matches();

    let mut expected: ByteArray = Default::default();
    expected.append_word('la', 2);
    expected.append_byte(ESCAPE_BYTE);
    expected.append_byte(0);
    expected.append_byte(0);
    expected.append_byte(5);
    expected.append_word('la', 2);

    assert(lz77.output == expected, 'unexpected result');
}

#[test]
#[available_gas(35000000)]
fn cycle_1() {
    let compressed = Lz77Encoder::encode(inputs::get_test_phrase_1());
    let decompressed = Lz77Decoder::decode(compressed);

    assert(decompressed == inputs::get_test_phrase_1(), 'unexpected result')
}

#[test]
#[available_gas(350000000)]
fn cycle_2() {
    let compressed = Lz77Encoder::encode(inputs::get_test_phrase_2());
    let decompressed = Lz77Decoder::decode(compressed);

    assert(decompressed == inputs::get_test_phrase_2(), 'unexpected result')
}

