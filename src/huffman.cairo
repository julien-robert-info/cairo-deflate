use nullable::FromNullableResult;
use dict::Felt252DictEntryTrait;
use compression::utils::{array_ext, sorting};
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
    codes: Felt252Dict<u16>,
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
    fn increment_codes_length(
        ref self: Huffman<T>, node: felt252, ref merged: Felt252Dict<Nullable<Span<felt252>>>
    ) -> Span<felt252>;
    fn get_codes_length(ref self: Huffman<T>);
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
    fn increment_codes_length(
        ref self: Huffman<ByteArray>,
        node: felt252,
        ref merged: Felt252Dict<Nullable<Span<felt252>>>
    ) -> Span<felt252> {
        match match_nullable(merged.get(node)) {
            //leave
            FromNullableResult::Null(()) => {
                let (entry, prev_value) = self.codes_length.entry(node);
                self.codes_length = entry.finalize(prev_value + 1);

                array![node].span()
            },
            //node
            FromNullableResult::NotNull(leaves) => {
                let mut leaves = leaves.unbox();
                let ret = leaves;
                loop {
                    match leaves.pop_front() {
                        Option::Some(leave) => {
                            let (entry, prev_value) = self.codes_length.entry(*leave);
                            self.codes_length = entry.finalize(prev_value + 1);
                        },
                        Option::None => { break; },
                    }
                };

                ret
            }
        }
    }
    fn get_codes_length(ref self: Huffman<ByteArray>) {
        let mut nodes = self.bytes.span();
        let mut merged: Felt252Dict<Nullable<Span<felt252>>> = Default::default();

        loop {
            if nodes.len() <= 1 {
                break;
            }

            //sort ASC on frequency value and ASC on key value
            nodes = sorting::bubble_sort_dict_keys(nodes, ref self.frequencies);

            match nodes.pop_front() {
                Option::Some(node) => {
                    let node1 = *node;
                    let node2 = *nodes[0];

                    //increment codes length and get sub leaves of merged nodes
                    let merge1 = self.increment_codes_length(node1, ref merged);
                    let merge2 = self.increment_codes_length(node2, ref merged);
                    //keep merged leaves in memory
                    let merge = array_ext::concat_span(merge1, merge2);
                    merged.insert(node2, nullable_from_box(BoxTrait::new(merge)));
                    //add frequencies of the two merged nodes
                    let freq1 = self.frequencies.get(node1);
                    let (entry, freq2) = self.frequencies.entry(node2);
                    self.frequencies = entry.finalize(freq1 + freq2);
                },
                Option::None => (),
            }
        }
    }
    fn set_codes(ref self: Huffman<ByteArray>) {
        //get codes length frequencies
        let mut codes_length_freq: Felt252Dict<u8> = Default::default();
        let mut bytes = sorting::bubble_sort_dict_keys(self.bytes.span(), ref self.codes_length);
        let mut codes_length = array![];
        loop {
            match bytes.pop_front() {
                Option::Some(byte) => {
                    let code_length = self.codes_length.get(*byte);
                    let (entry, freq) = codes_length_freq.entry(code_length.into());
                    if freq == 0 {
                        codes_length.append(code_length);
                    }
                    codes_length_freq = entry.finalize(freq + 1);
                },
                Option::None => { break; },
            }
        };
        //set starting codes
        let mut start_codes: Felt252Dict<u16> = Default::default();
        let mut c = 0;
        loop {
            match codes_length.pop_front() {
                Option::Some(code_length) => {
                    start_codes.insert(code_length.into(), c);
                    c = (c + codes_length_freq.get(code_length.into()).into()) * 2;
                },
                Option::None => { break; },
            }
        };
        //assign codes
        let mut empty_dict: Felt252Dict<u8> = Default::default();
        let mut bytes = sorting::bubble_sort_elements(self.bytes.span());
        loop {
            match bytes.pop_front() {
                Option::Some(byte) => {
                    let code_length = self.codes_length.get(*byte);
                    let (entry, code) = start_codes.entry(code_length.into());
                    self.codes.insert(*byte, code);
                    start_codes = entry.finalize(code + 1);
                },
                Option::None => { break; },
            }
        };
    }
}

impl HuffmanEncoder of Encoder<ByteArray> {
    fn encode(data: ByteArray) -> ByteArray {
        let mut huffman = HuffmanImpl::new(@data);
        huffman.get_frequencies();
        huffman.get_codes_length();
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
