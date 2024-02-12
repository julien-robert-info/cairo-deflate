use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::lz77::{Lz77Encoder, Lz77Decoder, Lz77Impl, Match};
use compression::utils::slice::ByteArraySliceImpl;
use compression::sequence::{ESCAPE_BYTE, Sequence};

#[test]
#[available_gas(500000)]
fn match_update() {
    let input = inputs::get_test_phrase_1();
    let mut lz77 = Lz77Impl::new(@input.slice(0, input.len()), Default::default());
    lz77.input_pos = 7;
    lz77.output_pos = 6;
    lz77.matches = array![Match { sequence: Sequence { length: 1, distance: 5 }, pos: 6 }];

    lz77.update_matches(lz77.input_read().unwrap());

    assert(lz77.matches.len() == 1, 'unexpected number of match 1');

    let mut matches = lz77.matches.span();
    let m = *matches.pop_front().unwrap();
    assert(m.sequence.length == 2, 'unexpected length 1');
    assert(m.sequence.distance == 5, 'unexpected distance 1');
    assert(m.pos == 7, 'unexpected pos 1');

    lz77.increment_pos();
    lz77.update_matches(lz77.input_read().unwrap());

    let mut matches = lz77.matches.span();
    let m = *matches.pop_front().unwrap();

    assert(m.sequence.length == 3, 'unexpected length 2');
    assert(m.sequence.distance == 5, 'unexpected distance 2');
    assert(m.pos == 8, 'unexpected pos 2');
}

#[test]
#[available_gas(500000)]
fn output_raw_sequence() {
    let input = inputs::get_test_phrase_1();
    let mut lz77 = Lz77Impl::new(@input.slice(0, input.len()), Default::default());
    lz77.input_pos = 7;

    lz77.output_raw_sequence(Sequence { length: 3, distance: 3 });

    let mut expected: ByteArray = Default::default();
    expected.append_word(' bl', 3);

    assert(lz77.output == expected, 'unexpected result');
}

#[test]
#[available_gas(1000000)]
fn process_matches() {
    let input = inputs::get_test_phrase_1();
    let mut lz77 = Lz77Impl::new(@input.slice(0, input.len()), Default::default());
    lz77.input_pos = 13;
    lz77.output_pos = 6;
    lz77.matches = array![Match { sequence: Sequence { length: 3, distance: 5 }, pos: 10 }];

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
    let input = inputs::get_test_phrase_1();
    let compressed = Lz77Encoder::encode(input.slice(0, input.len()), Default::default());
    let decompressed = Lz77Decoder::decode(compressed.slice(0, compressed.len()));

    assert(decompressed.unwrap() == inputs::get_test_phrase_1(), 'unexpected result')
}

#[test]
#[available_gas(350000000)]
fn cycle_2() {
    let input = inputs::get_test_phrase_2();
    let compressed = Lz77Encoder::encode(input.slice(0, input.len()), Default::default());
    let decompressed = Lz77Decoder::decode(compressed.slice(0, compressed.len()));

    assert(decompressed.unwrap() == inputs::get_test_phrase_2(), 'unexpected result')
}

