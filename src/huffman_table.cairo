use nullable::FromNullableResult;
use dict::Felt252DictEntryTrait;
use integer::u16_overflowing_sub;
use compression::commons::{ArrayTryInto, ArrayInto};
use compression::utils::sorting;
use compression::utils::dict_ext::{DictWithKeys, clone_from_keys};
use alexandria_math::pow;
use alexandria_sorting::bubble_sort::bubble_sort_elements;
use alexandria_data_structures::array_ext::{ArrayTraitExt, SpanTraitExt};
use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};

#[derive(Destruct)]
struct HuffmanTable {
    symbols: Array<felt252>,
    codes_length: Felt252Dict<u8>,
    codes: Felt252Dict<felt252>,
    decode: Felt252Dict<felt252>,
    max_code_length: u8
}

#[derive(Drop)]
enum HuffmanTableError {
    CodeNotFound: (felt252, u8),
    NotEnoughData
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
    fn build_from_frequencies(
        ref self: HuffmanTable, ref frequencies: DictWithKeys<u32>, max_code_length: u8
    );
    fn build_from_codes_length(ref self: HuffmanTable, max_code_length: u8);
    fn read_code(
        ref self: HuffmanTable, ref bit_stream: BitArray
    ) -> Result<felt252, HuffmanTableError>;
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
    fn build_from_frequencies(
        ref self: HuffmanTable, ref frequencies: DictWithKeys<u32>, max_code_length: u8
    ) {
        self.symbols = frequencies.keys.clone();
        self.max_code_length = max_code_length;
        self.get_codes_length(ref frequencies.dict);
        self.build_from_codes_length(max_code_length);
    }
    fn build_from_codes_length(ref self: HuffmanTable, max_code_length: u8) {
        self.max_code_length = max_code_length;
        self.set_codes();
        self.set_decode();
    }
    fn read_code(
        ref self: HuffmanTable, ref bit_stream: BitArray
    ) -> Result<felt252, HuffmanTableError> {
        let mut code_length = 0;
        let mut code = 0;

        loop {
            if code_length > self.max_code_length {
                break Result::Err(HuffmanTableError::CodeNotFound((code, code_length)));
            }

            match bit_stream.read_word_be(1) {
                Option::Some(bit) => {
                    code = code * 2 + bit;
                    code_length += 1;
                    let symbol = self.decode.get(code);
                    if self.codes.get(symbol) == code
                        && self.codes_length.get(symbol) == code_length {
                        break Result::Ok(symbol);
                    }
                },
                Option::None => { break Result::Err(HuffmanTableError::NotEnoughData); },
            }
        }
    }
}
