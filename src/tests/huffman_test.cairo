use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::utils::dict_ext::DictWithKeys;
use compression::huffman::{HuffmanEncoder, HuffmanDecoder, HuffmanImpl};

#[test]
#[available_gas(5000000)]
fn get_frequencies() {
    let mut huffman = HuffmanImpl::new(@inputs::get_test_phrase_3());
    let mut bytes_freq: DictWithKeys<u32> = Default::default();
    let mut offset_codes_freq: DictWithKeys<u32> = Default::default();

    huffman.get_frequencies(ref bytes_freq, ref offset_codes_freq);

    let bytes = array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'];
    let frequencies = array![3, 3, 2, 1, 1, 1, 1, 1];

    assert(bytes_freq.keys == bytes, 'unexcpected bytes');

    let mut i = 0;
    loop {
        if i >= bytes.len() - 1 {
            break;
        }

        assert(bytes_freq.dict.get(*bytes[i]) == *frequencies[i], 'unexpected bytes');
        i += 1;
    }
}

#[test]
#[available_gas(15000000)]
fn get_codes_length() {
    let mut huffman = HuffmanImpl::new(@inputs::get_test_phrase_3());

    let mut bytes_freq: DictWithKeys<u32> = Default::default();
    bytes_freq.keys = array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'];
    bytes_freq.dict.insert('g', 3);
    bytes_freq.dict.insert('o', 3);
    bytes_freq.dict.insert(' ', 2);
    bytes_freq.dict.insert('p', 1);
    bytes_freq.dict.insert('h', 1);
    bytes_freq.dict.insert('e', 1);
    bytes_freq.dict.insert('r', 1);
    bytes_freq.dict.insert('s', 1);

    let mut codes_length = huffman.get_codes_length(ref bytes_freq, 4);

    let expected_codes_length = array![2, 2, 3, 4, 4, 3, 4, 4];

    let mut i = 0;
    loop {
        if i >= bytes_freq.keys.len() - 1 {
            break;
        }

        assert(
            codes_length.get(*bytes_freq.keys[i]) == *expected_codes_length[i],
            'unexpected code length'
        );
        i += 1;
    }
}

#[test]
#[available_gas(2000000)]
fn set_codes() {
    let mut huffman = HuffmanImpl::new(@inputs::get_test_phrase_3());

    let mut codes_length: DictWithKeys<u8> = Default::default();
    codes_length.keys = array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'];
    codes_length.dict.insert('g', 2);
    codes_length.dict.insert('o', 2);
    codes_length.dict.insert(' ', 3);
    codes_length.dict.insert('p', 4);
    codes_length.dict.insert('h', 4);
    codes_length.dict.insert('e', 3);
    codes_length.dict.insert('r', 4);
    codes_length.dict.insert('s', 4);

    let mut codes = huffman.set_codes(ref codes_length, 4);

    let expected_codes = array![0, 1, 4, 13, 12, 5, 14, 15];

    let mut i = 0;
    loop {
        if i >= codes_length.keys.len() - 1 {
            break;
        }

        assert(codes.get(*codes_length.keys[i]) == *expected_codes[i], 'unexpected code');
        i += 1;
    }
}

#[test]
#[available_gas(70000000)]
fn max_code_length() {
    let mut huffman = HuffmanImpl::new(@Default::default());

    let mut bytes_freq: DictWithKeys<u32> = Default::default();
    bytes_freq
        .keys = array!['A', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S'];
    bytes_freq.dict.insert('A', 4);
    bytes_freq.dict.insert('D', 2);
    bytes_freq.dict.insert('E', 6);
    bytes_freq.dict.insert('F', 3);
    bytes_freq.dict.insert('G', 2);
    bytes_freq.dict.insert('H', 2);
    bytes_freq.dict.insert('J', 53);
    bytes_freq.dict.insert('K', 26);
    bytes_freq.dict.insert('L', 5);
    bytes_freq.dict.insert('M', 4);
    bytes_freq.dict.insert('N', 3);
    bytes_freq.dict.insert('P', 1);
    bytes_freq.dict.insert('Q', 1);
    bytes_freq.dict.insert('R', 1);
    bytes_freq.dict.insert('S', 37);

    let max_code_length = 7;

    let mut codes_length = huffman.get_codes_length(ref bytes_freq, max_code_length);

    let expected_codes_length = array![5, 7, 4, 6, 6, 6, 2, 2, 5, 5, 6, 7, 7, 7, 2].span();
    //without tree correction
    // let expected_codes_length = array![5, 6, 4, 6, 6, 6, 2, 2, 5, 5, 6, 7, 8, 8, 2].span();

    let mut i = 0;
    let bytes = bytes_freq.keys.span();
    loop {
        if i >= bytes.len() - 1 {
            break;
        }

        assert(codes_length.get(*bytes[i]) == *expected_codes_length[i], 'unexpected code length');
        i += 1;
    };

    let mut codes_length = DictWithKeys { dict: codes_length, keys: bytes_freq.keys };
    let mut codes = huffman.set_codes(ref codes_length, 7);

    let expected_codes = array![26, 124, 12, 58, 59, 60, 0, 1, 27, 28, 61, 125, 126, 127, 2];
    //without tree correction
    // let expected_codes = array![26, 58, 12, 59, 60, 61, 0, 1, 27, 28, 62, 126, 254, 255, 2];

    i = 0;
    loop {
        if i >= bytes.len() - 1 {
            break;
        }

        assert(codes.get(*bytes[i]) == *expected_codes[i], 'unexpected code');
        i += 1;
    };
}

#[test]
#[available_gas(700000000)]
fn test_huffman() {
    let compressed = HuffmanEncoder::encode(inputs::get_test_phrase_2());
// let decompressed = HuffmanDecoder::decode(compressed);

// assert(decompressed == inputs::get_test_phrase_1(), 'unexpected result')
}

