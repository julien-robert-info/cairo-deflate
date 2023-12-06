use dict::Felt252DictEntryTrait;
use compression::utils::sorting;
use compression::commons::{Encoder, Decoder};
use compression::offset_length_code::{ESCAPE_BYTE, CODE_BYTE_COUNT};

const LENGTH_BYTE_START: usize = 257;

#[derive(Destruct)]
struct Huffman<T> {
    length_codes: Array<u16>,
    offset_codes: Array<u16>,
    input: @T,
    output: T,
    frequencies: Felt252Dict<usize>,
    codes_length: Felt252Dict<u8>,
    codes: Felt252Dict<felt252>,
    bytes: Array<felt252>,
    input_pos: usize,
}

trait HuffmanTrait<T> {
    fn set_length_codes() -> Array<u16>;
    fn set_offset_codes() -> Array<u16>;
    fn new(input: @T) -> Huffman<T>;
    fn input_read(ref self: Huffman<T>) -> Option<u8>;
    fn is_escaped(ref self: Huffman<T>) -> bool;
    fn decode_length_offset(ref self: Huffman<T>) -> (u16, u16);
    fn get_length_code(self: @Huffman<T>, value: u16) -> felt252;
    fn get_offset_code(self: @Huffman<T>, value: u16) -> felt252;
    fn get_frequencies(ref self: Huffman<T>);
    fn set_codes(ref self: Huffman<T>);
}

impl HuffmanImpl of HuffmanTrait<ByteArray> {
    #[inline(always)]
    fn set_length_codes() -> Array<u16> {
        array![
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            10,
            12,
            14,
            16,
            20,
            24,
            28,
            32,
            40,
            48,
            56,
            64,
            80,
            96,
            112,
            128,
            160,
            192,
            224,
            254,
            255
        ]
    }
    #[inline(always)]
    fn set_offset_codes() -> Array<u16> {
        array![
            2,
            3,
            4,
            5,
            7,
            9,
            13,
            17,
            25,
            33,
            49,
            65,
            97,
            129,
            193,
            257,
            385,
            513,
            769,
            1025,
            1537,
            2049,
            3073,
            4097,
            6145,
            8193,
            12289,
            16385,
            24577,
            32769
        ]
    }
    #[inline(always)]
    fn new(input: @ByteArray) -> Huffman<ByteArray> {
        Huffman {
            length_codes: HuffmanImpl::set_length_codes(),
            offset_codes: HuffmanImpl::set_offset_codes(),
            input: input,
            output: Default::default(),
            frequencies: Default::default(),
            codes_length: Default::default(),
            codes: Default::default(),
            bytes: array![],
            input_pos: 0,
        }
    }
    #[inline(always)]
    fn input_read(ref self: Huffman<ByteArray>) -> Option<u8> {
        let byte = self.input.at(self.input_pos);
        self.input_pos += 1;

        byte
    }
    #[inline(always)]
    fn is_escaped(ref self: Huffman<ByteArray>) -> bool {
        match self.input.at(self.input_pos + 1) {
            Option::Some(next_byte) => {
                if next_byte == ESCAPE_BYTE {
                    return true;
                } else {
                    return false;
                }
            },
            Option::None => false,
        }
    }
    #[inline(always)]
    fn decode_length_offset(ref self: Huffman<ByteArray>) -> (u16, u16) {
        let byte_left = self.input.len() - self.input_pos;
        assert(byte_left >= CODE_BYTE_COUNT, 'Not enougth bytes to read');
        self.input_pos += 1;
        let length: u16 = self.input_read().unwrap().into();
        let mut offset: u16 = self.input_read().unwrap().into();
        offset = offset * 256 + self.input_read().unwrap().into();

        (length, offset)
    }
    fn get_length_code(self: @Huffman<ByteArray>, value: u16) -> felt252 {
        let mut i: u32 = 0;
        let length_codes = self.length_codes;
        loop {
            if value < *length_codes.at(i) {
                break;
            }
            i += 1;
        };

        (LENGTH_BYTE_START + i).into()
    }
    fn get_offset_code(self: @Huffman<ByteArray>, value: u16) -> felt252 {
        let mut i: u32 = 0;
        let offset_codes = self.offset_codes;
        loop {
            if value < *offset_codes.at(i) {
                break;
            }
            i += 1;
        };

        i.into()
    }
    fn get_frequencies(ref self: Huffman<ByteArray>) {
        match self.input_read() {
            Option::Some(byte) => {
                let felt_byte: felt252 = byte.into();

                if byte == ESCAPE_BYTE && !self.is_escaped() {
                    // get length and offset codes
                    let (length, offset) = self.decode_length_offset();
                    let length_code = self.get_length_code(length);
                    let offset_code = self.get_offset_code(offset);
                    //increment length and offset codes frequency
                    let (entry, prev_value) = self.frequencies.entry(length_code);
                    self.frequencies = entry.finalize(prev_value + 1);
                    let (entry, prev_value) = self.frequencies.entry(offset_code);
                    self.frequencies = entry.finalize(prev_value + 1);
                } else {
                    //increment byte frequency
                    let (entry, prev_value) = self.frequencies.entry(felt_byte);
                    if prev_value == 0 {
                        self.bytes.append(felt_byte);
                    }
                    self.frequencies = entry.finalize(prev_value + 1);
                }

                self.get_frequencies();
            },
            Option::None(()) => (),
        }
    }
    fn set_codes(ref self: Huffman<ByteArray>) {
        //create Code list and counts
        self.get_frequencies();
        //sort bytes
        self.bytes = sorting::bubble_sort_dict_keys_desc(self.bytes, ref self.frequencies);
    //get codes length
    //assign code
    }
}

impl HuffmanEncoder of Encoder<ByteArray> {
    fn encode(data: ByteArray) -> ByteArray {
        let mut huffman = HuffmanImpl::new(@data);
        huffman.set_codes();

        huffman.output
    }
}

impl HuffmanDecoder of Decoder<ByteArray> {
    fn decode(data: ByteArray) -> ByteArray {
        let mut huffman = HuffmanImpl::new(@data);

        huffman.output
    }
}
