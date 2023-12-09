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

        assert(huffman.frequencies.get(*bytes.at(i)) == *frequencies.at(i), 'unexpected bytes');
        i += 1;
    }
}

#[test]
#[available_gas(10000000)]
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
            huffman.codes_length.get(*huffman.bytes.at(i)) == *codes_length.at(i),
            'unexpected code length'
        );
        i += 1;
    }
}

#[test]
#[available_gas(300000000)]
fn test_huffman() {
    let compressed = HuffmanEncoder::encode(inputs::get_test_phrase_3());
// let decompressed = HuffmanDecoder::decode(compressed);

// assert(decompressed == inputs::get_test_phrase_1(), 'unexpected result')
}

