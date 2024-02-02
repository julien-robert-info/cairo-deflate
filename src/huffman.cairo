use nullable::FromNullableResult;
use dict::Felt252DictEntryTrait;
use integer::{u16_overflowing_sub, u32_overflowing_sub};
use compression::utils::sorting;
use compression::utils::dict_ext::{DictWithKeys, clone_from_keys};
use compression::commons::{Encoder, Decoder, ArrayTryInto, ArrayInto};
use compression::deflate::magic_array;
use compression::sequence::{ESCAPE_BYTE, SEQUENCE_BYTE_COUNT, Sequence, SequenceImpl};
use alexandria_math::pow;
use alexandria_sorting::bubble_sort::bubble_sort_elements;
use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};
use alexandria_data_structures::array_ext::{ArrayTraitExt, SpanTraitExt};

const LENGTH_BYTE_START: u32 = 257;
const END_OF_BLOCK: felt252 = 256;

#[derive(Destruct)]
struct HuffmanTable {
    symbols: Array<felt252>,
    codes_length: Felt252Dict<u8>,
    codes: Felt252Dict<felt252>,
    decode: Felt252Dict<felt252>,
    max_code_length: u8
}

impl HuffmanTableDefault of Default<HuffmanTable> {
    #[inline(always)]
    fn default() -> HuffmanTable {
        HuffmanTable {
            symbols: array![],
            codes_length: Default::default(),
            codes: Default::default(),
            decode: Default::default(),
            max_code_length: 0
        }
    }
}

trait HuffmanTableTrait {
    fn increment_codes_length(ref self: HuffmanTable, nodes: Span<felt252>) -> bool;
    fn get_codes_length_frequencies(ref self: HuffmanTable) -> Felt252Dict<u8>;
    fn adjust_tree_structure(ref self: HuffmanTable, ref frequencies: Felt252Dict<u32>);
    fn get_codes_length(ref self: HuffmanTable, ref frequencies: Felt252Dict<u32>);
    fn set_codes(ref self: HuffmanTable);
    fn set_decode(ref self: HuffmanTable);
    fn build(ref self: HuffmanTable, ref frequencies: DictWithKeys<u32>, max_code_length: u8);
// fn decode_symbol(
//     ref self: HuffmanTable, bit_stream: BitArray
// ) -> Result<felt252, HuffmanTableError>;
}

impl HuffmanTableImpl of HuffmanTableTrait {
    fn increment_codes_length(ref self: HuffmanTable, nodes: Span<felt252>) -> bool {
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
    fn get_codes_length_frequencies(ref self: HuffmanTable) -> Felt252Dict<u8> {
        let mut codes_length_freq: Felt252Dict<u8> = Default::default();
        let mut symbols = self.symbols.span();

        loop {
            match symbols.pop_front() {
                Option::Some(symbol) => {
                    let code_length = self.codes_length.get(*symbol);
                    let (entry, freq) = codes_length_freq.entry(code_length.into());
                    codes_length_freq = entry.finalize(freq + 1);
                },
                Option::None => { break; },
            }
        };

        codes_length_freq
    }
    fn adjust_tree_structure(ref self: HuffmanTable, ref frequencies: Felt252Dict<u32>) {
        let mut symbols = sorting::bubble_sort_dict_keys(self.symbols.clone(), ref frequencies);
        symbols = symbols.reverse();
        symbols = sorting::bubble_sort_dict_keys(symbols, ref self.codes_length);
        symbols = symbols.reverse();

        let mut codes_length_freq = self.get_codes_length_frequencies();
        let mut i: u16 = self.max_code_length.into();
        let mut prev_s = pow(2, i) * 2;

        loop {
            if i == 0 {
                break;
            }
            let n: u16 = codes_length_freq.get(i.into()).into();
            let mut s = match u16_overflowing_sub((prev_s / 2), n) {
                Result::Ok(x) => x,
                Result::Err(x) => 1,
            };

            // if starting code for length n is not even
            if s & 1 != 0 {
                //elevate next least frequent symbol
                let mut symbols = symbols.span();
                loop {
                    match symbols.pop_front() {
                        Option::Some(symbol) => {
                            let symbol = *symbol;
                            let code_length: u16 = self.codes_length.get(symbol).into();

                            if code_length < i {
                                self.increment_codes_length(array![symbol].span());

                                codes_length_freq = self.get_codes_length_frequencies();
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
    fn get_codes_length(ref self: HuffmanTable, ref frequencies: Felt252Dict<u32>) {
        let keys = @self.symbols;
        if keys.len() == 1 {
            self.increment_codes_length(keys.span());
            return;
        }

        let mut merged_freq = clone_from_keys(keys, ref frequencies);
        let mut nodes = self.symbols.clone();
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
                    merge = sorting::bubble_sort_dict_keys(merge, ref frequencies);
                    merge = merge.reverse();
                    merge = sorting::bubble_sort_dict_keys(merge, ref self.codes_length);
                    merge = merge.reverse();

                    merged = entry.finalize(nullable_from_box(BoxTrait::new(merge.span())));

                    //increment codes length of merged leaves
                    let max_length_reached = self.increment_codes_length(merge.span());

                    if max_length_reached {
                        self.adjust_tree_structure(ref frequencies);
                    }
                },
                Option::None => (),
            }
        }
    }
    fn set_codes(ref self: HuffmanTable) {
        let mut codes_length_freq = self.get_codes_length_frequencies();
        //set starting codes
        let mut start_codes: Felt252Dict<u32> = Default::default();
        let mut code: u32 = 0;
        let mut i = 1;
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
        let symbols: Array<u128> = (@self.symbols).try_into().unwrap();
        let symbols: Array<felt252> = (@bubble_sort_elements(symbols)).into();
        let mut symbols = symbols.span();
        loop {
            match symbols.pop_front() {
                Option::Some(symbol) => {
                    let symbol = *symbol;
                    let code_length = self.codes_length.get(symbol);
                    let (entry, code) = start_codes.entry(code_length.into());
                    self.codes.insert(symbol, code.into());
                    start_codes = entry.finalize(code + 1);
                },
                Option::None => { break; },
            }
        }
    }
    fn set_decode(ref self: HuffmanTable) {
        let mut symbols = self.symbols.span();
        loop {
            match symbols.pop_front() {
                Option::Some(symbol) => {
                    let symbol = *symbol;
                    let code = self.codes.get(symbol);
                    self.decode.insert(code, symbol);
                },
                Option::None => { break; },
            }
        }
    }
    fn build(ref self: HuffmanTable, ref frequencies: DictWithKeys<u32>, max_code_length: u8) {
        self.symbols = frequencies.keys.clone();
        self.max_code_length = max_code_length;
        self.get_codes_length(ref frequencies.dict);
        self.set_codes();
        self.set_decode();
    }
// fn decode_symbol(
//     ref self: HuffmanTable, bit_stream: BitArray
// ) -> Result<felt252, HuffmanTableError> {}
}

#[derive(Destruct)]
struct Huffman<T> {
    input: @T,
    bit_stream: BitArray,
    litterals: HuffmanTable,
    distances: HuffmanTable,
    bit_length: HuffmanTable,
    bit_length_array: Array<u8>,
    repeat_values: Array<u8>,
    input_pos: usize
}

trait HuffmanTrait<T> {
    fn new(input: @T) -> Huffman<T>;
    fn input_read(ref self: Huffman<T>) -> Option<u8>;
    fn is_escaped(ref self: Huffman<T>) -> bool;
    fn read_sequence(ref self: Huffman<T>) -> Sequence;
    fn get_frequencies(
        ref self: Huffman<T>, ref litterals: DictWithKeys<u32>, ref distances: DictWithKeys<u32>
    );
    fn build_tables(ref self: Huffman<T>, max_code_length: u8);
    fn bit_length_table(ref self: Huffman<T>, max_bit_length: u8) -> (u32, u32);
}

impl HuffmanImpl of HuffmanTrait<ByteArray> {
    #[inline(always)]
    fn new(input: @ByteArray) -> Huffman<ByteArray> {
        Huffman {
            input: input,
            bit_stream: Default::default(),
            litterals: Default::default(),
            distances: Default::default(),
            bit_length: Default::default(),
            bit_length_array: Default::default(),
            repeat_values: Default::default(),
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
    fn read_sequence(ref self: Huffman<ByteArray>) -> Sequence {
        let byte_left = self.input.len() - self.input_pos;
        assert(byte_left >= CODE_BYTE_COUNT, 'Not enougth bytes to read');
        let length: usize = self.input_read().unwrap().into();
        let mut distance: usize = self.input_read().unwrap().into();
        distance = distance * 256 + self.input_read().unwrap().into();

        Sequence { length: length, distance: distance }
    }
    fn get_frequencies(
        ref self: Huffman<ByteArray>,
        ref litterals: DictWithKeys<u32>,
        ref distances: DictWithKeys<u32>
    ) {
        match self.input_read() {
            Option::Some(byte) => {
                let felt_byte: felt252 = byte.into();

                if byte != ESCAPE_BYTE {
                    //increment byte frequency
                    let (entry, prev_value) = litterals.dict.entry(felt_byte);
                    if prev_value == 0 {
                        litterals.keys.append(felt_byte);
                    }
                    litterals.dict = entry.finalize(prev_value + 1);
                } else {
                    if !self.is_escaped() {
                        // get length and distance codes
                        let sequence = self.read_sequence();
                        let (length_code, length_extra_bits) = sequence.get_length_code();
                        let (distance_code, distance_extra_bits) = sequence.get_distance_code();
                        //increment length and distance codes frequency
                        let (entry, prev_value) = litterals.dict.entry(length_code);
                        litterals.dict = entry.finalize(prev_value + 1);
                        let (entry, prev_value) = distances.dict.entry(distance_code);
                        if prev_value == 0 {
                            distances.keys.append(distance_code);
                        }
                        distances.dict = entry.finalize(prev_value + 1);
                    } else {
                        let (entry, prev_value) = litterals.dict.entry(felt_byte);
                        if prev_value == 0 {
                            litterals.keys.append(felt_byte);
                        }
                        litterals.dict = entry.finalize(prev_value + 2);
                        self.input_pos += 1;
                    }
                }

                self.get_frequencies(ref litterals, ref distances);
            },
            Option::None(()) => (),
        }
    }
    fn build_tables(ref self: Huffman<ByteArray>, max_code_length: u8) {
        let mut litterals_freq: DictWithKeys<u32> = Default::default();
        let mut distances_freq: DictWithKeys<u32> = Default::default();
        self.get_frequencies(ref litterals_freq, ref distances_freq);
        if distances_freq.keys.is_empty() {
            distances_freq.keys.append(0);
            distances_freq.dict.insert(0, 1);
        }

        litterals_freq.keys.append(END_OF_BLOCK);
        litterals_freq.dict.insert(END_OF_BLOCK, 1);

        self.litterals.build(ref litterals_freq, max_code_length);
        self.distances.build(ref distances_freq, max_code_length);
    }
    fn bit_length_table(ref self: Huffman<ByteArray>, max_bit_length: u8) -> (u32, u32) {
        //define hlit and hdist
        let lit_sortable: Array<u32> = (@self.litterals.symbols).try_into().unwrap();
        let lit_max = lit_sortable.max().unwrap();
        let hlit = if lit_max <= LENGTH_BYTE_START {
            LENGTH_BYTE_START
        } else {
            lit_max
        };

        let distances_sortable: Array<u32> = (@self.distances.symbols).try_into().unwrap();
        let hdist = distances_sortable.max().unwrap() + 1;

        //hlit + hdist length array of code_length
        let mut bit_length_array = array![];
        let mut i = 0;
        loop {
            if i >= hlit {
                break;
            }
            bit_length_array.append(self.litterals.codes_length.get(i.into()));

            i += 1;
        };

        i = 0;
        loop {
            if i >= hdist {
                break;
            }
            bit_length_array.append(self.distances.codes_length.get(i.into()));

            i += 1;
        };

        //apply repeat codes
        let mut codes_length_span = bit_length_array.span();
        bit_length_array = array![];
        let mut prev = 19;
        let mut repeat_count: u8 = 0;
        let mut repeat_values: Array<u8> = array![];

        loop {
            match codes_length_span.pop_front() {
                Option::Some(code_length) => {
                    let code_length = *code_length;

                    if code_length == prev {
                        repeat_count += 1;
                    } else {
                        if repeat_count > 3 && prev != 0 {
                            bit_length_array.append(prev);
                            bit_length_array.append(16);

                            if repeat_count <= 6 {
                                repeat_values.append(repeat_count);
                                repeat_count = 0;
                            } else {
                                repeat_values.append(6);
                                repeat_count = repeat_count - 6;
                            }
                        } else if repeat_count >= 3 && prev == 0 {
                            if repeat_count < 11 {
                                bit_length_array.append(17);
                                repeat_values.append(repeat_count);
                                repeat_count = 0;
                            } else {
                                bit_length_array.append(18);

                                if repeat_count <= 138 {
                                    repeat_values.append(repeat_count);
                                    repeat_count = 0;
                                } else {
                                    repeat_values.append(138);
                                    repeat_count = repeat_count - 138;
                                }
                            }
                        } else if prev != 19 {
                            let mut j = 0;
                            loop {
                                if j > repeat_count {
                                    break;
                                }
                                bit_length_array.append(prev);

                                j += 1;
                            };

                            repeat_count = 0;
                        }
                    }

                    prev = code_length;
                },
                Option::None => {
                    let mut j = 0;
                    loop {
                        if j > repeat_count {
                            break;
                        }
                        bit_length_array.append(prev);

                        j += 1;
                    };
                    break;
                },
            };
        };
        self.bit_length_array = bit_length_array.clone();
        self.repeat_values = repeat_values;

        //build table
        let mut codes_length_dict: Felt252Dict<u8> = Default::default();
        let mut symbols: Array<felt252> = array![];
        i = 0;
        loop {
            if i >= bit_length_array.len() {
                break;
            }
            let felt_i: felt252 = i.into();
            symbols.append(felt_i);
            codes_length_dict.insert(felt_i, *bit_length_array[i]);

            i += 1;
        };

        let magic_array = magic_array();
        let mut table = HuffmanTable {
            symbols: magic_array.clone(),
            codes_length: codes_length_dict,
            codes: Default::default(),
            decode: Default::default(),
            max_code_length: 0
        };
        let mut frequency_dict = table.get_codes_length_frequencies();

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
        self.bit_length.build(ref frequencies, 7);
        (hlit, hdist)
    }
}

impl HuffmanEncoder of Encoder<ByteArray> {
    fn encode(data: ByteArray) -> ByteArray {
        let max_code_length = 15;
        let max_bit_length = 7;
        let mut huffman = HuffmanImpl::new(@data);
        huffman.build_tables(max_code_length);
        let (hlit, hdist) = huffman.bit_length_table(max_bit_length);

        let symbols = @huffman.bit_length.symbols;
        let mut hclen = symbols.len() - 1;
        loop {
            if huffman.bit_length.codes_length.get(*symbols[hclen]) > 0 {
                break;
            }

            hclen -= 1;
        };

        huffman.bit_stream.write_word_be((hlit - LENGTH_BYTE_START).into(), 5);
        huffman.bit_stream.write_word_be((hdist - 1).into(), 5);
        huffman.bit_stream.write_word_be((hclen - 4).into(), 4);

        let magic_array = magic_array();
        let mut i = 0;
        loop {
            if i >= hclen {
                break;
            }
            huffman
                .bit_stream
                .write_word_be(
                    huffman.bit_length.codes_length.get((*magic_array[i]).into()).into(), 3
                );

            i += 1;
        };

        let mut span = huffman.bit_length_array.span();
        let mut repeat_values = huffman.repeat_values.span();
        loop {
            match span.pop_front() {
                Option::Some(symbol) => {
                    let symbol = *symbol;
                    let felt_symbol = symbol.into();
                    let code_length = huffman.bit_length.codes_length.get(felt_symbol);
                    let code = huffman.bit_length.codes.get(felt_symbol);
                    huffman.bit_stream.write_word_be(code.into(), code_length.into());

                    if symbol > 15 {
                        let val = *repeat_values.pop_front().unwrap();
                        if symbol == 16 {
                            huffman.bit_stream.write_word_be((val - 3).into(), 2);
                        } else if symbol == 17 {
                            huffman.bit_stream.write_word_be((val - 3).into(), 3);
                        } else if symbol == 18 {
                            huffman.bit_stream.write_word_be((val - 11).into(), 7);
                        }
                    }
                },
                Option::None => { break; },
            };
        };
        huffman.input_pos = 0;
        loop {
            match huffman.input_read() {
                Option::Some(byte) => {
                    let felt_byte: felt252 = byte.into();
                    if byte != ESCAPE_BYTE {
                        //output code
                        let code_length = huffman.litterals.codes_length.get(felt_byte);
                        let code = huffman.litterals.codes.get(felt_byte);
                        huffman.bit_stream.write_word_be(code.into(), code_length.into());
                    } else {
                        if !huffman.is_escaped() {
                            // get length and distance codes
                            let sequence = huffman.read_sequence();
                            let (length_code, length_extra_bits) = sequence.get_length_code();
                            let (distance_code, distance_extra_bits) = sequence.get_distance_code();
                            //output length and distance codes with extra bits
                            let mut code_length = huffman.litterals.codes_length.get(length_code);
                            let mut code = huffman.litterals.codes.get(length_code);
                            huffman.bit_stream.write_word_be(code.into(), code_length.into());
                            if length_extra_bits.bits > 0 {
                                huffman
                                    .bit_stream
                                    .write_word_be(length_extra_bits.value, length_extra_bits.bits);
                            }

                            code_length = huffman.distances.codes_length.get(length_code);
                            code = huffman.distances.codes.get(length_code);
                            huffman.bit_stream.write_word_be(code.into(), code_length.into());
                            if distance_extra_bits.bits > 0 {
                                huffman
                                    .bit_stream
                                    .write_word_be(
                                        distance_extra_bits.value, distance_extra_bits.bits
                                    );
                            }
                        } else {
                            //output ESCAPE_BYTE code
                            let code_length = huffman.litterals.codes_length.get(felt_byte);
                            let code = huffman.litterals.codes.get(felt_byte);
                            huffman.bit_stream.write_word_be(code.into(), code_length.into());
                            huffman.input_pos += 1;
                        }
                    }
                },
                Option::None(()) => { break; },
            };
        };

        let code_length = huffman.litterals.codes_length.get(END_OF_BLOCK);
        let code = huffman.litterals.codes.get(END_OF_BLOCK);
        huffman.bit_stream.write_word_be(code.into(), code_length.into());

        huffman.bit_stream.into()
    }
}
