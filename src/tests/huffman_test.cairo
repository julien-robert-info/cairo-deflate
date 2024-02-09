use compression::tests::inputs;
use compression::commons::{Encoder, Decoder};
use compression::huffman::{HuffmanEncoder, HuffmanDecoder, HuffmanImpl};
use compression::huffman_table::{HuffmanTable, HuffmanTableImpl};
use compression::lz77::{Lz77Encoder, Lz77Decoder};
use compression::utils::dict_ext::DictWithKeys;
use compression::utils::slice::ByteArraySliceImpl;

#[test]
#[available_gas(7000000)]
fn get_frequencies() {
    let input = inputs::get_test_phrase_3();
    let mut huffman = HuffmanImpl::new(@input.slice(0, input.len()));
    let mut bytes_freq: DictWithKeys<u32> = Default::default();
    let mut distance_codes_freq: DictWithKeys<u32> = Default::default();

    huffman.get_frequencies(ref bytes_freq, ref distance_codes_freq);

    let bytes = array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'];
    let expected_frequencies = array![3, 3, 2, 1, 1, 1, 1, 1];

    assert(bytes_freq.keys == bytes, 'unexcpected bytes');

    let mut i = 0;
    loop {
        if i >= bytes.len() - 1 {
            break;
        }

        assert(bytes_freq.dict.get(*bytes[i]) == *expected_frequencies[i], 'unexpected bytes');
        i += 1;
    }
}

#[test]
#[available_gas(15000000)]
fn get_codes_length() {
    let mut table = HuffmanTable {
        symbols: array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'],
        codes_length: Default::default(),
        codes: Default::default(),
        decode: Default::default(),
        max_code_length: 4
    };

    let mut frequencies: Felt252Dict<u32> = Default::default();
    frequencies.insert('g', 3);
    frequencies.insert('o', 3);
    frequencies.insert(' ', 2);
    frequencies.insert('p', 1);
    frequencies.insert('h', 1);
    frequencies.insert('e', 1);
    frequencies.insert('r', 1);
    frequencies.insert('s', 1);

    table.get_codes_length(ref frequencies);

    let expected_codes_length = array![2, 2, 3, 4, 4, 3, 4, 4];

    let mut i = 0;
    loop {
        if i >= table.symbols.len() - 1 {
            break;
        }

        assert(
            table.codes_length.get(*table.symbols[i]) == *expected_codes_length[i],
            'unexpected code length'
        );
        i += 1;
    }
}

#[test]
#[available_gas(2000000)]
fn set_codes() {
    let mut codes_length: Felt252Dict<u8> = Default::default();
    codes_length.insert('g', 2);
    codes_length.insert('o', 2);
    codes_length.insert(' ', 3);
    codes_length.insert('p', 4);
    codes_length.insert('h', 4);
    codes_length.insert('e', 3);
    codes_length.insert('r', 4);
    codes_length.insert('s', 4);

    let mut table = HuffmanTable {
        symbols: array!['g', 'o', ' ', 'p', 'h', 'e', 'r', 's'],
        codes_length: codes_length,
        codes: Default::default(),
        decode: Default::default(),
        max_code_length: 4
    };

    table.set_codes();

    let expected_codes = array![0, 1, 4, 13, 12, 5, 14, 15];

    let mut i = 0;
    loop {
        if i >= table.symbols.len() - 1 {
            break;
        }

        assert(table.codes.get(*table.symbols[i]) == *expected_codes[i], 'unexpected code');
        i += 1;
    }
}

#[test]
#[available_gas(70000000)]
fn max_code_length() {
    let mut table: HuffmanTable = Default::default();
    let max_code_length = 7;
    let mut frequencies: DictWithKeys<u32> = Default::default();
    frequencies
        .keys = array!['A', 'D', 'E', 'F', 'G', 'H', 'J', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'S'];
    frequencies.dict.insert('A', 4);
    frequencies.dict.insert('D', 2);
    frequencies.dict.insert('E', 6);
    frequencies.dict.insert('F', 3);
    frequencies.dict.insert('G', 2);
    frequencies.dict.insert('H', 2);
    frequencies.dict.insert('J', 53);
    frequencies.dict.insert('K', 26);
    frequencies.dict.insert('L', 5);
    frequencies.dict.insert('M', 4);
    frequencies.dict.insert('N', 3);
    frequencies.dict.insert('P', 1);
    frequencies.dict.insert('Q', 1);
    frequencies.dict.insert('R', 1);
    frequencies.dict.insert('S', 37);

    table.build_from_frequencies(ref frequencies, max_code_length);

    let expected_codes_length = array![5, 7, 4, 6, 6, 6, 2, 2, 5, 5, 6, 7, 7, 7, 2].span();
    //without tree correction
    // let expected_codes_length = array![5, 6, 4, 6, 6, 6, 2, 2, 5, 5, 6, 7, 8, 8, 2].span();

    let mut i = 0;
    let symbols = table.symbols.span();
    loop {
        if i >= symbols.len() - 1 {
            break;
        }

        assert(
            table.codes_length.get(*symbols[i]) == *expected_codes_length[i],
            'unexpected code length'
        );
        i += 1;
    };

    let expected_codes = array![26, 124, 12, 58, 59, 60, 0, 1, 27, 28, 61, 125, 126, 127, 2];
    //without tree correction
    // let expected_codes = array![26, 58, 12, 59, 60, 61, 0, 1, 27, 28, 62, 126, 254, 255, 2];

    i = 0;
    loop {
        if i >= table.symbols.len() - 1 {
            break;
        }

        assert(table.codes.get(*table.symbols[i]) == *expected_codes[i], 'unexpected code');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000)]
fn test_huffman() {
    let input = inputs::get_test_phrase_2();
    let compressed = HuffmanEncoder::encode(input.slice(0, input.len()));
    let decompressed = HuffmanDecoder::decode(compressed.slice(0, compressed.len()));

    assert(decompressed.unwrap() == inputs::get_test_phrase_2(), 'unexpected result')
}

#[test]
#[available_gas(1500000000)]
fn test_huffman_with_lz77() {
    let input = inputs::get_test_phrase_2();
    let lz77 = Lz77Encoder::encode(input.slice(0, input.len()));
    let huffman = HuffmanEncoder::encode(lz77.slice(0, lz77.len()));

    let huffman_decompressed = HuffmanDecoder::decode(huffman.slice(0, huffman.len()));
    let huffman_decompressed = huffman_decompressed.unwrap();
    let lz77_decompressed = Lz77Decoder::decode(
        huffman_decompressed.slice(0, huffman_decompressed.len())
    );
    let lz77_decompressed = lz77_decompressed.unwrap();

    assert(lz77_decompressed == inputs::get_test_phrase_2(), 'unexpected result')
}

