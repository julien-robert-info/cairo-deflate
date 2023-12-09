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
#[available_gas(300000000)]
fn test_huffman() {
    let compressed = HuffmanEncoder::encode(inputs::get_test_phrase_2());
// let decompressed = HuffmanDecoder::decode(compressed);

// assert(decompressed == inputs::get_test_phrase_1(), 'unexpected result')
}
