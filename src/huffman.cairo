use nullable::FromNullableResult;
use dict::Felt252DictEntryTrait;
use integer::u32_overflowing_sub;
use compression::utils::sorting;
use compression::utils::dict_ext::{DictWithKeys, clone_from_keys};
use compression::commons::{Encoder, Decoder, ArrayTryInto, ArrayInto};
use compression::deflate::magic_array;
use compression::offset_length_code::{
    ESCAPE_BYTE, CODE_BYTE_COUNT, MIN_CODE_LEN, OLCode, OLCodeImpl
};
use alexandria_math::pow;
use alexandria_sorting::bubble_sort::bubble_sort_elements;
use alexandria_data_structures::array_ext::{ArrayTraitExt, SpanTraitExt};

const LENGTH_BYTE_START: u32 = 257;
const END_OF_BLOCK: felt252 = 256;

#[derive(Destruct)]
struct HuffmanTable {
    symbols: Array<felt252>,
    codes_length: Felt252Dict<u8>,
    codes: Felt252Dict<u32>
}

impl HuffmanTableDefault of Default<HuffmanTable> {
    #[inline(always)]
    fn default() -> HuffmanTable {
        HuffmanTable {
            symbols: array![], codes_length: Default::default(), codes: Default::default()
        }
    }
}

#[derive(Destruct)]
struct Huffman<T> {
    input: @T,
    litterals: HuffmanTable,
    offsets: HuffmanTable,
    bit_length: HuffmanTable,
    output: T,
    input_pos: usize
}

trait HuffmanTrait<T> {
    fn new(input: @T) -> Huffman<T>;
    fn input_read(ref self: Huffman<T>) -> Option<u8>;
    fn is_escaped(ref self: Huffman<T>) -> bool;
    fn read_code(ref self: Huffman<T>) -> OLCode;
    fn get_frequencies(
        ref self: Huffman<T>, ref bytes: DictWithKeys<u32>, ref offset_codes: DictWithKeys<u32>
    );
    fn increment_codes_length(
        ref self: Huffman<T>,
        ref codes_length: Felt252Dict<u8>,
        nodes: Span<felt252>,
        max_code_length: u8
    ) -> bool;
    fn get_codes_length_frequencies(
        ref self: Huffman<T>, ref codes_length: Felt252Dict<u8>, bytes: @Array<felt252>
    ) -> Felt252Dict<u8>;
    fn get_codes_length(
        ref self: Huffman<T>, ref frequencies: DictWithKeys<u32>, max_code_length: u8
    ) -> Felt252Dict<u8>;
    fn set_codes(
        ref self: Huffman<T>, ref codes_length: DictWithKeys<u8>, max_code_length: u8
    ) -> Felt252Dict<u32>;
    fn init_tables(
        ref self: Huffman<T>, max_code_length: u8, max_offset_code_length: u8, max_bit_length: u8
    );
    fn bit_length_table(ref self: Huffman<T>, max_bit_length: u8);
}

impl HuffmanImpl of HuffmanTrait<ByteArray> {
    #[inline(always)]
    fn new(input: @ByteArray) -> Huffman<ByteArray> {
        Huffman {
            input: input,
            litterals: Default::default(),
            offsets: Default::default(),
            bit_length: Default::default(),
            output: Default::default(),
            input_pos: 0
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
    fn read_code(ref self: Huffman<ByteArray>) -> OLCode {
        let byte_left = self.input.len() - self.input_pos;
        assert(byte_left >= CODE_BYTE_COUNT, 'Not enougth bytes to read');
        let length: usize = self.input_read().unwrap().into();
        let mut offset: usize = self.input_read().unwrap().into();
        offset = offset * 256 + self.input_read().unwrap().into();

        OLCode { length: length, offset: offset }
    }
    fn get_frequencies(
        ref self: Huffman<ByteArray>,
        ref bytes: DictWithKeys<u32>,
        ref offset_codes: DictWithKeys<u32>
    ) {
        match self.input_read() {
            Option::Some(byte) => {
                let felt_byte: felt252 = byte.into();

                if byte == ESCAPE_BYTE {
                    if !self.is_escaped() {
                        // get length and offset codes
                        let sequence = self.read_code();
                        let length_code = sequence.get_length_code();
                        let offset_code = sequence.get_offset_code();
                        //increment length and offset codes frequency
                        let (entry, prev_value) = bytes
                            .dict
                            .entry((length_code + LENGTH_BYTE_START).into());
                        bytes.dict = entry.finalize(prev_value + 1);
                        let (entry, prev_value) = offset_codes.dict.entry(offset_code.into());
                        if prev_value == 0 {
                            offset_codes.keys.append(offset_code.into());
                        }
                        offset_codes.dict = entry.finalize(prev_value + 1);
                    } else {
                        let (entry, prev_value) = bytes.dict.entry(felt_byte);
                        if prev_value == 0 {
                            bytes.keys.append(felt_byte);
                        }
                        bytes.dict = entry.finalize(prev_value + 2);
                        self.input_pos += 1;
                    }
                } else {
                    //increment byte frequency
                    let (entry, prev_value) = bytes.dict.entry(felt_byte);
                    if prev_value == 0 {
                        bytes.keys.append(felt_byte);
                    }
                    bytes.dict = entry.finalize(prev_value + 1);
                }

                self.get_frequencies(ref bytes, ref offset_codes);
            },
            Option::None(()) => (),
        }
    }
    fn increment_codes_length(
        ref self: Huffman<ByteArray>,
        ref codes_length: Felt252Dict<u8>,
        nodes: Span<felt252>,
        max_code_length: u8
    ) -> bool {
        let mut nodes = nodes;
        let mut max_length_reached = false;

        match nodes.pop_front() {
            Option::Some(node) => {
                let (entry, mut code_length) = codes_length.entry(*node);
                if code_length < max_code_length {
                    code_length += 1;
                } else {
                    max_length_reached = true;
                }
                codes_length = entry.finalize(code_length);

                let max_length_reached_r = self
                    .increment_codes_length(ref codes_length, nodes, max_code_length);
                max_length_reached = max_length_reached || max_length_reached_r;
            },
            Option::None(()) => (),
        }

        max_length_reached
    }
    fn get_codes_length_frequencies(
        ref self: Huffman<ByteArray>, ref codes_length: Felt252Dict<u8>, bytes: @Array<felt252>,
    ) -> Felt252Dict<u8> {
        let mut codes_length_freq: Felt252Dict<u8> = Default::default();
        let mut bytes = bytes.span();

        loop {
            match bytes.pop_front() {
                Option::Some(byte) => {
                    let code_length = codes_length.get(*byte);
                    let (entry, freq) = codes_length_freq.entry(code_length.into());
                    codes_length_freq = entry.finalize(freq + 1);
                },
                Option::None => { break; },
            }
        };

        codes_length_freq
    }
    fn get_codes_length(
        ref self: Huffman<ByteArray>, ref frequencies: DictWithKeys<u32>, max_code_length: u8
    ) -> Felt252Dict<u8> {
        let mut codes_length: Felt252Dict<u8> = Default::default();
        let keys = @frequencies.keys;
        let mut merged_freq = clone_from_keys(keys, ref frequencies.dict);
        let mut nodes = frequencies.keys.clone();
        let mut merged: Felt252Dict<Nullable<Span<felt252>>> = Default::default();

        loop {
            if nodes.len() <= 1 {
                break;
            }

            //sort ASC on frequency value and DESC on key value
            let mut sortable_nodes: Array<u128> = (@nodes).try_into().unwrap();
            sortable_nodes = bubble_sort_elements(sortable_nodes);
            sortable_nodes = sortable_nodes.reverse();
            nodes = (@sortable_nodes).into();
            nodes = sorting::bubble_sort_dict_keys(nodes, ref merged_freq);

            match nodes.pop_front() {
                Option::Some(node) => {
                    let node1 = node;
                    let node2 = *nodes[0];

                    //combine frequencies of the two merged nodes
                    let freq1 = merged_freq.get(node1);
                    let (entry, freq2) = merged_freq.entry(node2);
                    merged_freq = entry.finalize(freq1 + freq2);

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
                    merge = sorting::bubble_sort_dict_keys(merge, ref frequencies.dict);
                    merge = merge.reverse();
                    merge = sorting::bubble_sort_dict_keys(merge, ref codes_length);
                    merge = merge.reverse();

                    merged = entry.finalize(nullable_from_box(BoxTrait::new(merge.span())));

                    //increment codes length of merged leaves
                    let max_length_reached = self
                        .increment_codes_length(ref codes_length, merge.span(), max_code_length);
                    //if max_code_length reached, verify node structure
                    if max_length_reached {
                        let mut codes_length_freq = self
                            .get_codes_length_frequencies(ref codes_length, keys);
                        let mut i: u16 = max_code_length.into();
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
                                            let code_length: u16 = codes_length.get(node).into();

                                            if code_length == (i - 1) {
                                                self
                                                    .increment_codes_length(
                                                        ref codes_length,
                                                        array![node].span(),
                                                        max_code_length
                                                    );

                                                codes_length_freq = self
                                                    .get_codes_length_frequencies(
                                                        ref codes_length, keys
                                                    );
                                                i = (max_code_length + 1).into();
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
        };

        codes_length
    }
    fn set_codes(
        ref self: Huffman<ByteArray>, ref codes_length: DictWithKeys<u8>, max_code_length: u8
    ) -> Felt252Dict<u32> {
        let mut codes_length_freq = self
            .get_codes_length_frequencies(ref codes_length.dict, @codes_length.keys);
        //set starting codes
        let mut start_codes: Felt252Dict<u32> = Default::default();
        let mut code: u32 = 0;
        let mut i = 1;
        loop {
            if i > max_code_length {
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
        let mut codes: Felt252Dict<u32> = Default::default();
        let bytes: Array<u128> = (@codes_length.keys).try_into().unwrap();
        let mut bytes: Array<felt252> = (@bubble_sort_elements(bytes)).into();
        loop {
            match bytes.pop_front() {
                Option::Some(byte) => {
                    let code_length = codes_length.dict.get(byte);
                    let (entry, code) = start_codes.entry(code_length.into());
                    codes.insert(byte, code);
                    start_codes = entry.finalize(code + 1);
                },
                Option::None => { break; },
            }
        };

        codes
    }
    fn init_tables(
        ref self: Huffman<ByteArray>,
        max_code_length: u8,
        max_offset_code_length: u8,
        max_bit_length: u8
    ) {
        let mut bytes_freq: DictWithKeys<u32> = Default::default();
        let mut offset_codes_freq: DictWithKeys<u32> = Default::default();
        self.get_frequencies(ref bytes_freq, ref offset_codes_freq);

        bytes_freq.keys.append(END_OF_BLOCK);
        bytes_freq.dict.insert(END_OF_BLOCK, 1);

        let bytes_codes_length = self.get_codes_length(ref bytes_freq, max_code_length);
        let mut bytes_codes_length = DictWithKeys {
            dict: bytes_codes_length, keys: bytes_freq.keys.clone()
        };
        let mut bytes_codes = self.set_codes(ref bytes_codes_length, max_code_length);
        self
            .litterals =
                HuffmanTable {
                    symbols: bytes_freq.keys,
                    codes_length: bytes_codes_length.dict,
                    codes: bytes_codes
                };

        let mut offset_codes_length = self
            .get_codes_length(ref offset_codes_freq, max_offset_code_length);
        let mut offset_codes_length = DictWithKeys {
            dict: offset_codes_length, keys: offset_codes_freq.keys.clone()
        };
        let mut offset_codes = self.set_codes(ref offset_codes_length, max_offset_code_length);
        self
            .offsets =
                HuffmanTable {
                    symbols: offset_codes_freq.keys,
                    codes_length: offset_codes_length.dict,
                    codes: offset_codes
                };

        self.bit_length_table(max_bit_length);
    }
    fn bit_length_table(ref self: Huffman<ByteArray>, max_bit_length: u8) {
        //hlit + hdist length array of code_length
        let mut code_length_array = array![];
        let mut span = self.litterals.symbols.span();
        loop {
            match span.pop_front() {
                Option::Some(symbol) => code_length_array
                    .append(self.litterals.codes_length.get(*symbol)),
                Option::None => { break; },
            }
        };
        span = self.offsets.symbols.span();
        loop {
            match span.pop_front() {
                Option::Some(symbol) => code_length_array
                    .append(self.offsets.codes_length.get(*symbol)),
                Option::None => { break; },
            }
        };

        //apply repeat codes
        let mut codes_length_span = code_length_array.span();
        code_length_array = array![];
        let mut prev = 19;
        let mut repeat_count: u32 = 0;
        let mut repeat_values = array![];

        loop {
            match codes_length_span.pop_front() {
                Option::Some(code_length) => {
                    let code_length = *code_length;

                    if code_length == prev {
                        repeat_count += 1;
                    } else {
                        if repeat_count > 3 && code_length != 0 {
                            code_length_array.append(code_length);
                            code_length_array.append(16);

                            if repeat_count <= 6 {
                                repeat_values.append(repeat_count);
                                repeat_count = 0;
                            } else {
                                repeat_values.append(6);
                                repeat_count = repeat_count - 6;
                            }
                        } else if repeat_count >= 3 && code_length == 0 {
                            if repeat_count < 11 {
                                code_length_array.append(17);
                                repeat_values.append(repeat_count);
                                repeat_count = 0;
                            } else {
                                code_length_array.append(18);

                                if repeat_count <= 138 {
                                    repeat_values.append(repeat_count);
                                    repeat_count = 0;
                                } else {
                                    repeat_values.append(138);
                                    repeat_count = repeat_count - 138;
                                }
                            }
                        } else {
                            let mut j = 0;
                            loop {
                                if j >= repeat_count {
                                    break;
                                }
                                code_length_array.append(code_length);

                                j += 1;
                            };
                        }
                    }

                    prev = code_length;
                },
                Option::None => { break; },
            };
        };

        let mut codes_length_dict: Felt252Dict<u8> = Default::default();
        let mut symbols: Array<felt252> = array![];
        let mut i = 0;
        loop {
            if i >= code_length_array.len() {
                break;
            }
            let felt_i: felt252 = i.into();
            symbols.append(felt_i);
            codes_length_dict.insert(felt_i, *code_length_array[i]);

            i += 1;
        };

        let magic_array = magic_array();
        let mut frequency_dict = self.get_codes_length_frequencies(ref codes_length_dict, @symbols);

        let mut codes_length_freq: Felt252Dict<u32> = Default::default();
        let mut span = magic_array.span();
        loop {
            match span.pop_front() {
                Option::Some(code_length) => {
                    let code_length = *code_length;
                    codes_length_freq.insert(code_length, frequency_dict.get(code_length).into());
                },
                Option::None => { break; },
            }
        };

        let mut frequencies = DictWithKeys { keys: magic_array.clone(), dict: codes_length_freq };
        let mut codes_length = self.get_codes_length(ref frequencies, 7);
        let mut codes_length = DictWithKeys { keys: frequencies.keys, dict: codes_length };
        let mut codes = self.set_codes(ref codes_length, 7);

        self
            .bit_length =
                HuffmanTable {
                    symbols: codes_length.keys, codes_length: codes_length_dict, codes: codes
                };
    }
}

impl HuffmanEncoder of Encoder<ByteArray> {
    fn encode(data: ByteArray) -> ByteArray {
        let mut huffman = HuffmanImpl::new(@data);
        let max_code_length = 15;
        let max_bit_length = 7;
        huffman.init_tables(max_code_length, max_code_length, max_bit_length);

        huffman.output
    }
}

impl HuffmanDecoder of Decoder<ByteArray> {
    fn decode(data: ByteArray) -> ByteArray {
        let mut huffman = HuffmanImpl::new(@data);

        huffman.output
    }
}
