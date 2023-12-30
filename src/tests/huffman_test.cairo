use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::huffman::{HuffmanEncoder, HuffmanDecoder, HuffmanImpl};

#[test]
#[available_gas(5000000)]
fn get_frequencies() {
    let mut huffman = HuffmanImpl::new(@inputs::get_test_phrase_3());

    huffman.get_frequencies();

    let bytes = array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'];
    let frequencies = array![3, 3, 2, 1, 1, 1, 1, 1];

    assert(huffman.bytes == bytes, 'unexcpected bytes');

    let mut i = 0;
    loop {
        if i >= bytes.len() - 1 {
            break;
        }

        assert(huffman.frequencies.get(*bytes[i]) == *frequencies[i], 'unexpected bytes');
        i += 1;
    }
}

#[test]
#[available_gas(15000000)]
fn get_codes_length() {
    let mut huffman = HuffmanImpl::new(@inputs::get_test_phrase_3());

    huffman.bytes = array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'];
    huffman.frequencies.insert('g', 3);
    huffman.frequencies.insert('o', 3);
    huffman.frequencies.insert(' ', 2);
    huffman.frequencies.insert('p', 1);
    huffman.frequencies.insert('h', 1);
    huffman.frequencies.insert('e', 1);
    huffman.frequencies.insert('r', 1);
    huffman.frequencies.insert('s', 1);

    huffman.get_codes_length();

    let codes_length = array![2, 2, 3, 4, 4, 3, 4, 4];

    let mut i = 0;
    loop {
        if i >= huffman.bytes.len() - 1 {
            break;
        }

        assert(
            huffman.codes_length.get(*huffman.bytes[i]) == *codes_length[i],
            'unexpected code length'
        );
        i += 1;
    }
}

#[test]
#[available_gas(3000000)]
fn set_codes() {
    let mut huffman = HuffmanImpl::new(@inputs::get_test_phrase_3());

    huffman.bytes = array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'];
    huffman.codes_length.insert('g', 2);
    huffman.codes_length.insert('o', 2);
    huffman.codes_length.insert(' ', 3);
    huffman.codes_length.insert('p', 4);
    huffman.codes_length.insert('h', 4);
    huffman.codes_length.insert('e', 3);
    huffman.codes_length.insert('r', 4);
    huffman.codes_length.insert('s', 4);

    huffman.set_codes();

    let codes = array![0, 1, 4, 13, 12, 5, 14, 15];

    let mut i = 0;
    loop {
        if i >= huffman.bytes.len() - 1 {
            break;
        }

        assert(huffman.codes.get(*huffman.bytes[i]) == *codes[i], 'unexpected code');
        i += 1;
    }
}

#[test]
#[available_gas(70000000)]
fn max_code_length() {
    let mut huffman = HuffmanImpl::new(@Default::default());

    huffman
        .bytes = array!['A', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S'];
    huffman.frequencies.insert('A', 4);
    huffman.frequencies.insert('D', 2);
    huffman.frequencies.insert('E', 6);
    huffman.frequencies.insert('F', 3);
    huffman.frequencies.insert('G', 2);
    huffman.frequencies.insert('H', 2);
    huffman.frequencies.insert('J', 53);
    huffman.frequencies.insert('K', 26);
    huffman.frequencies.insert('L', 5);
    huffman.frequencies.insert('M', 4);
    huffman.frequencies.insert('N', 3);
    huffman.frequencies.insert('P', 1);
    huffman.frequencies.insert('Q', 1);
    huffman.frequencies.insert('R', 1);
    huffman.frequencies.insert('S', 37);

    huffman.max_code_length = 7;

    huffman.get_codes_length();

    let codes_length = array![5, 6, 4, 6, 6, 7, 2, 2, 5, 5, 6, 7, 7, 7, 2].span();
    //without tree correction
    // let codes_length = array![5, 6, 4, 6, 6, 6, 2, 2, 5, 5, 6, 7, 8, 8, 2].span();

    let mut i = 0;
    let bytes = huffman.bytes.span();
    loop {
        if i >= bytes.len() - 1 {
            break;
        }

        assert(huffman.codes_length.get(*bytes[i]) == *codes_length[i], 'unexpected code length');
        i += 1;
    };

    huffman.set_codes();

    let codes = array![26, 58, 12, 59, 60, 124, 0, 1, 27, 28, 61, 125, 126, 127, 2];
    //without tree correction
    // let codes = array![26, 58, 12, 59, 60, 61, 0, 1, 27, 28, 62, 126, 254, 255, 2];

    i = 0;
    loop {
        if i >= bytes.len() - 1 {
            break;
        }
        assert(huffman.codes.get(*bytes[i]) == *codes[i], 'unexpected code');
        i += 1;
    };
}

#[test]
#[available_gas(20000000)]
fn test_huffman() {
    let compressed = HuffmanEncoder::encode(inputs::get_test_phrase_3());
// let decompressed = HuffmanDecoder::decode(compressed);

// assert(decompressed == inputs::get_test_phrase_1(), 'unexpected result')
}

