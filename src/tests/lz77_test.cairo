use compression::commons::Encoder;
use compression::lz77::Lz77Encoder;

#[test]
// #[available_gas(17000000)]
// fn test_lz77_compress_1() {
//     let compressed = Lz77Encoder::encode(get_test_phrase_1());
//     let expected = get_compressed_phrase_1();

//     assert(compressed == expected, 'unexpected result')
// }

#[test]
#[available_gas(1000000000)]
fn test_lz77_compress_1() {
    let compressed = Lz77Encoder::encode(get_test_phrase_2());
    let expected = get_compressed_phrase_2();

    assert(compressed == expected, 'unexpected result')
}

fn get_test_phrase_1() -> ByteArray {
    let mut test_phrase: ByteArray = Default::default();
    test_phrase.append_word('Blah blah blah blah blah!', 25);

    test_phrase
}

fn get_compressed_phrase_1() -> ByteArray {
    let mut compressed_phrase: ByteArray = Default::default();
    compressed_phrase.append_word('Blah b<5,12>!', 13);

    compressed_phrase
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

fn get_compressed_phrase_2() -> ByteArray {
    let mut compressed_phrase: ByteArray = Default::default();
    compressed_phrase.append_word('Four score and seven years ago ', 31);
    compressed_phrase.append_word('<30,4>fathe<16,3>brought forth,', 31);
    compressed_phrase.append_word(' on this continent, a new natio', 31);
    compressed_phrase.append_word('n,<25,4>ceived in Liberty<36,3>', 31);
    compressed_phrase.append_word('<102,3>dedicat<26,3>to<69,3>e p', 31);
    compressed_phrase.append_word('roposi<56,4><85,3>at all m<138,', 31);
    compressed_phrase.append_word('3>a<152,3>cre<44,5>equal.', 25);

    compressed_phrase
}
