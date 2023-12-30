use nullable::FromNullableResult;
use dict::Felt252DictEntryTrait;
use compression::utils::{dict_ext, sorting};
use compression::commons::{Encoder, Decoder, ArrayTryInto, ArrayInto};
use compression::offset_length_code::{ESCAPE_BYTE, CODE_BYTE_COUNT};
use alexandria_math::pow;
use alexandria_sorting::bubble_sort::bubble_sort_elements;
use alexandria_data_structures::array_ext::{ArrayTraitExt, SpanTraitExt};

const LENGTH_BYTE_START: usize = 257;

#[derive(Destruct)]
struct Huffman<T> {
    length_codes: Array<u16>,
    offset_codes: Array<u16>,
    input: @T,
    output: T,
    frequencies: Felt252Dict<u32>,
    codes_length: Felt252Dict<u8>,
    codes: Felt252Dict<u32>,
    bytes: Array<felt252>,
    input_pos: usize,
    max_code_length: u8
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
    fn increment_codes_length(ref self: Huffman<T>, nodes: Span<felt252>) -> bool;
    fn get_codes_length_frequencies(ref self: Huffman<T>) -> Felt252Dict<u8>;
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
            max_code_length: 15
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
        let mut i: usize = 0;
        let length_codes = self.length_codes;
        loop {
            if value < *length_codes[i] {
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
            if value < *offset_codes[i] {
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
    fn increment_codes_length(ref self: Huffman<ByteArray>, nodes: Span<felt252>) -> bool {
        let mut nodes = nodes;
        let mut max_length_reached = false;
        match nodes.pop_front() {
            Option::Some(node) => {
                let (entry, mut code_length) = self.codes_length.entry(*node);
                if code_length < self.max_code_length {
                    code_length += 1;
                } else {
                    max_length_reached = true;
                }
                self.codes_length = entry.finalize(code_length);
                let max_length_reached_r = self.increment_codes_length(nodes);
                max_length_reached = max_length_reached || max_length_reached_r;
            },
            Option::None(()) => (),
        }

        max_length_reached
    }
    fn get_codes_length_frequencies(ref self: Huffman<ByteArray>) -> Felt252Dict<u8> {
        let mut codes_length_freq: Felt252Dict<u8> = Default::default();
        let mut bytes = self.bytes.clone();
        bytes = sorting::bubble_sort_dict_keys(bytes, ref self.codes_length);

        loop {
            match bytes.pop_front() {
                Option::Some(byte) => {
                    let code_length = self.codes_length.get(byte);
                    let (entry, freq) = codes_length_freq.entry(code_length.into());
                    codes_length_freq = entry.finalize(freq + 1);
                },
                Option::None => { break; },
            }
        };

        codes_length_freq
    }
    fn get_codes_length(ref self: Huffman<ByteArray>) {
        let mut frequencies = dict_ext::clone_from_keys(@self.bytes, ref self.frequencies);
        let mut nodes = self.bytes.clone();
        let mut merged: Felt252Dict<Nullable<Span<felt252>>> = Default::default();

        loop {
            if nodes.len() <= 1 {
                break;
            }

            //sort ASC on frequency value and DESC on key value
            let mut sortable_nodes: Array<u128> = (@nodes).try_into().unwrap();
            sortable_nodes = bubble_sort_elements(sortable_nodes);
            sortable_nodes = sortable_nodes.reverse();
            nodes = sortable_nodes.into();
            nodes = sorting::bubble_sort_dict_keys(nodes, ref frequencies);

            match nodes.pop_front() {
                Option::Some(node) => {
                    let node1 = node;
                    let node2 = *nodes[0];

                    //combine frequencies of the two merged nodes
                    let freq1 = frequencies.get(node1);
                    let (entry, freq2) = frequencies.entry(node2);
                    frequencies = entry.finalize(freq1 + freq2);

                    //combine merged leaves
                    let merge1 = match match_nullable(merged.get(node1)) {
                        FromNullableResult::Null(()) => array![node1].span(),
                        FromNullableResult::NotNull(leaves) => leaves.unbox()
                    };
                    let (entry, merge2) = merged.entry(node2);
                    let merge2 = match match_nullable(merge2) {
                        FromNullableResult::Null(()) => array![node2].span(),
                        FromNullableResult::NotNull(leaves) => leaves.unbox()
                    };
                    let mut merge = merge1.concat(merge2).dedup();
                    //sort by code length DESC, frequency ASC
                    merge = sorting::bubble_sort_dict_keys(merge, ref self.frequencies);
                    merge = merge.reverse();
                    merge = sorting::bubble_sort_dict_keys(merge, ref self.codes_length);
                    merge = merge.reverse();

                    merged = entry.finalize(nullable_from_box(BoxTrait::new(merge.span())));

                    //increment codes length of merged leaves
                    let max_length_reached = self.increment_codes_length(merge.span());
                    //if max_code_length reached, verify node structure
                    if max_length_reached {
                        let mut codes_length_freq = self.get_codes_length_frequencies();
                        let mut i: u16 = self.max_code_length.into();
                        let mut prev_s = pow(2, i) * 2;
                        loop {
                            if i == 0 {
                                break;
                            }
                            let n: u16 = codes_length_freq.get(i.into()).into();
                            let mut s = (prev_s / 2) - n;
                            // if starting code for length n is not even
                            if s & 1 != 0 {
                                //elevate next least frequent symbol
                                let mut merge_span = merge.span();
                                loop {
                                    match merge_span.pop_front() {
                                        Option::Some(node) => {
                                            let node = *node;
                                            let code_length: u16 = self
                                                .codes_length
                                                .get(node)
                                                .into();

                                            if code_length == (i - 1) {
                                                self.increment_codes_length(array![node].span());

                                                codes_length_freq = self
                                                    .get_codes_length_frequencies();
                                                i = (self.max_code_length + 1).into();
                                                s = pow(2, i) * 2;
                                                break;
                                            }
                                        },
                                        Option::None => { break; },
                                    };
                                };
                            }
                            prev_s = s;
                            i -= 1;
                        };
                    }
                },
                Option::None => (),
            }
        }
    }
    fn set_codes(ref self: Huffman<ByteArray>) {
        let mut codes_length_freq = self.get_codes_length_frequencies();
        //set starting codes
        let mut start_codes: Felt252Dict<u32> = Default::default();
        let mut code: u32 = 0;
        let mut i = 0;
        loop {
            if i > self.max_code_length {
                break;
            }
            let code_length_freq = codes_length_freq.get(i.into());
            if code_length_freq != 0 {
                start_codes.insert(i.into(), code);
            }
            code = (code + code_length_freq.into()) * 2;
            i += 1;
        };
        //assign codes
        let bytes: Array<u128> = (@self.bytes).try_into().unwrap();
        let mut bytes: Array<felt252> = bubble_sort_elements(bytes).into();
        loop {
            match bytes.pop_front() {
                Option::Some(byte) => {
                    let code_length = self.codes_length.get(byte);
                    let (entry, code) = start_codes.entry(code_length.into());
                    self.codes.insert(byte, code);
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
