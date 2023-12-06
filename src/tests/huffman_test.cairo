use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::huffman::{HuffmanEncoder, HuffmanDecoder};

#[test]
#[available_gas(300000000)]
fn test_huffman() {
    let compressed = HuffmanEncoder::encode(inputs::get_test_phrase_2());
// let decompressed = HuffmanDecoder::decode(compressed);

// assert(decompressed == inputs::get_test_phrase_1(), 'unexpected result')
}
