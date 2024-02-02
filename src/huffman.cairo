use nullable::FromNullableResult;
use dict::Felt252DictEntryTrait;
use compression::utils::dict_ext::DictWithKeys;
use compression::utils::byte_array_ext::{BitArrayIntoByteArray, ByteArrayIntoBitArray};
use compression::commons::{Encoder, Decoder, ArrayTryInto, ArrayInto};
use compression::deflate::magic_array;
use compression::huffman_table::{HuffmanTable, HuffmanTableImpl, HuffmanTableError};
use compression::sequence::{ESCAPE_BYTE, SEQUENCE_BYTE_COUNT, Sequence, SequenceImpl};
use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};
use alexandria_data_structures::array_ext::ArrayTraitExt;

const LENGTH_BYTE_START: u32 = 257;
const END_OF_BLOCK: felt252 = 256;

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

#[derive(Drop)]
enum HuffmanError {
    NotEnoughData,
    HuffmanTableError: HuffmanTableError,
    inconsistantTable
}

trait HuffmanTrait<T> {
    fn new(input: @T) -> Huffman<T>;
    fn input_read(ref self: Huffman<T>) -> Option<u8>;
    fn is_escaped(ref self: Huffman<T>) -> bool;
    fn read_sequence(ref self: Huffman<T>) -> Result<Sequence, HuffmanError>;
    fn get_frequencies(
        ref self: Huffman<T>, ref litterals: DictWithKeys<u32>, ref distances: DictWithKeys<u32>
    );
    fn build_tables(ref self: Huffman<T>, max_code_length: u8);
    fn bit_length_table(ref self: Huffman<T>, max_bit_length: u8) -> (u32, u32);
    fn restore_tables(input: T) -> Result<Huffman<T>, HuffmanError>;
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
    fn read_sequence(ref self: Huffman<ByteArray>) -> Result<Sequence, HuffmanError> {
        let byte_left = self.input.len() - self.input_pos;
        if byte_left < SEQUENCE_BYTE_COUNT {
            return Result::Err(HuffmanError::NotEnoughData);
        }

        let length: usize = self.input_read().unwrap().into();
        let mut distance: usize = self.input_read().unwrap().into();
        distance = distance * 256 + self.input_read().unwrap().into();

        Result::Ok(Sequence { length: length, distance: distance })
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
                        let sequence = self.read_sequence().unwrap();
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

        self.litterals.build_from_frequencies(ref litterals_freq, max_code_length);
        self.distances.build_from_frequencies(ref distances_freq, max_code_length);
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
        self.bit_length.build_from_frequencies(ref frequencies, 7);
        (hlit, hdist)
    }
    fn restore_tables(input: ByteArray) -> Result<Huffman<ByteArray>, HuffmanError> {
        let mut huffman = Huffman {
            input: @input,
            bit_stream: input.into(),
            litterals: Default::default(),
            distances: Default::default(),
            bit_length: Default::default(),
            bit_length_array: Default::default(),
            repeat_values: Default::default(),
            input_pos: 0
        };

        if huffman.bit_stream.len() < 14 {
            return Result::Err(HuffmanError::NotEnoughData);
        }

        let hlit: u32 = huffman.bit_stream.read_word_be(5).unwrap().try_into().unwrap()
            + LENGTH_BYTE_START;
        let hdist: u32 = huffman.bit_stream.read_word_be(5).unwrap().try_into().unwrap() + 1;
        let hclen: u32 = huffman.bit_stream.read_word_be(4).unwrap().try_into().unwrap() + 4;

        if huffman.bit_stream.len() < hclen * 3 {
            return Result::Err(HuffmanError::NotEnoughData);
        }

        let magic_array = @magic_array();
        let mut i = 0;
        loop {
            if i >= hclen {
                break;
            }
            let symbol: felt252 = (*magic_array[i]).into();
            let code_length: u8 = huffman.bit_stream.read_word_be(3).unwrap().try_into().unwrap();
            huffman.bit_length.symbols.append(symbol);
            huffman.bit_length.codes_length.insert(symbol, code_length);

            i += 1;
        };

        huffman.bit_length.build_from_codes_length(7);

        let mut bit_length_array = array![];
        let result = loop {
            if bit_length_array.len() >= hlit + hdist {
                break Result::Ok(());
            }

            match huffman.bit_length.read_code(ref huffman.bit_stream) {
                Result::Ok(symbol) => {
                    let symbol: u32 = symbol.try_into().unwrap();

                    if symbol < 15 {
                        bit_length_array.append(symbol);
                    } else {
                        let mut j = 0;
                        if symbol == 16 {
                            let repeat_values: u32 = huffman
                                .bit_stream
                                .read_word_be(2)
                                .unwrap()
                                .try_into()
                                .unwrap()
                                + 3;
                            let value = *bit_length_array[(bit_length_array.len() - 1)];
                            loop {
                                if j > repeat_values {
                                    break;
                                }
                                bit_length_array.append(value);

                                j += 1;
                            }
                        } else if symbol == 17 {
                            let repeat_values: u32 = huffman
                                .bit_stream
                                .read_word_be(3)
                                .unwrap()
                                .try_into()
                                .unwrap()
                                + 3;
                            loop {
                                if j > repeat_values {
                                    break;
                                }
                                bit_length_array.append(0);

                                j += 1;
                            }
                        } else if symbol == 18 {
                            let repeat_values: u32 = huffman
                                .bit_stream
                                .read_word_be(7)
                                .unwrap()
                                .try_into()
                                .unwrap()
                                + 11;
                            loop {
                                if j > repeat_values {
                                    break;
                                }
                                bit_length_array.append(0);

                                j += 1;
                            }
                        }
                    }
                },
                Result::Err(err) => { break Result::Err(HuffmanError::HuffmanTableError(err)); }
            }
        };

        if result.is_err() {
            return Result::Err(result.unwrap_err());
        }

        let codes_length = @bit_length_array;
        i = 0;
        loop {
            if i >= hlit {
                break;
            }
            let code_length = *codes_length[i];
            if code_length > 0 {
                huffman.litterals.symbols.append(i.into());
                huffman.litterals.codes_length.insert(i.into(), code_length.try_into().unwrap());
            }

            i += 1;
        };
        huffman.litterals.build_from_codes_length(15);

        loop {
            if i >= hlit + hdist {
                break;
            }
            let code_length = *codes_length[i];
            if code_length > 0 {
                huffman.distances.symbols.append(i.into());
                huffman.distances.codes_length.insert(i.into(), code_length.try_into().unwrap());
            }

            i += 1;
        };
        huffman.distances.build_from_codes_length(15);

        Result::Ok(huffman)
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
                            let sequence = huffman.read_sequence().unwrap();
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

impl HuffmanDecoder of Decoder<ByteArray, HuffmanError> {
    fn decode(data: ByteArray) -> Result<ByteArray, HuffmanError> {
        let mut result = HuffmanImpl::restore_tables(data);
        match result {
            Result::Ok(mut huffman) => {
                let mut output: ByteArray = Default::default();

                loop {
                    match huffman.litterals.read_code(ref huffman.bit_stream) {
                        Result::Ok(symbol) => {
                            if symbol == END_OF_BLOCK {
                                break Result::Ok(output.clone());
                            }

                            let symbol: u8 = symbol.try_into().unwrap();
                            if symbol != ESCAPE_BYTE {
                                output.append_byte(symbol);
                            } else {
                                //read sequence values
                                let mut next_symbol = huffman
                                    .litterals
                                    .read_code(ref huffman.bit_stream);

                                if next_symbol.is_err() {
                                    break Result::Err(
                                        HuffmanError::HuffmanTableError(next_symbol.unwrap_err())
                                    );
                                }
                                let next_symbol: u8 = next_symbol.unwrap().try_into().unwrap();

                                if next_symbol != ESCAPE_BYTE {
                                    let length_code: felt252 = next_symbol.into();
                                    let mut distance_code = huffman
                                        .distances
                                        .read_code(ref huffman.bit_stream);

                                    if distance_code.is_err() {
                                        break Result::Err(
                                            HuffmanError::HuffmanTableError(
                                                distance_code.unwrap_err()
                                            )
                                        );
                                    }

                                    let (sequence, length_extra_bits, distance_extra_bits) =
                                        SequenceImpl::new(
                                        length_code, distance_code.unwrap()
                                    );

                                    let extra_length: u32 = huffman
                                        .bit_stream
                                        .read_word_be(length_extra_bits)
                                        .unwrap()
                                        .try_into()
                                        .unwrap();

                                    let extra_distance: u32 = huffman
                                        .bit_stream
                                        .read_word_be(distance_extra_bits)
                                        .unwrap()
                                        .try_into()
                                        .unwrap();

                                    let sequence = Sequence {
                                        length: sequence.length + extra_length,
                                        distance: sequence.distance + extra_distance
                                    };
                                    //output sequence into byte array
                                    let byte_sequence: ByteArray = sequence.into();
                                    output.append(@byte_sequence);
                                } else {
                                    output.append_byte(ESCAPE_BYTE);
                                }
                            }
                        },
                        Result::Err(err) => {
                            break Result::Err(HuffmanError::HuffmanTableError(err));
                        }
                    };
                }
            },
            Result::Err(err) => Result::Err(err)
        }
    }
}
