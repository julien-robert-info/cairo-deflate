use nullable::FromNullableResult;
use dict::{Felt252DictTrait, Felt252DictEntryTrait};
use integer::u32_overflowing_sub;
use compression::commons::Encoder;

use debug::PrintTrait;

const WINDOW_SIZE: usize = 1024;
const MIN_MATCH_LEN: usize = 3;

#[derive(Copy, Drop)]
struct Match {
    distance: usize,
    length: usize
}

#[derive(Destruct)]
struct Lz77<T> {
    input: @T,
    output: T,
    matches: Array<Match>,
    char_pos: Felt252Dict<Nullable<Span<usize>>>,
    cur_pos: usize
}

trait Lz77Trait<T> {
    fn new(input: @T) -> Lz77<T>;
    fn window_start(self: @Lz77<T>) -> usize;
    fn next_byte(ref self: Lz77<T>) -> Option<u8>;
    fn increment_pos(ref self: Lz77<T>);
    fn get_char_pos(ref self: Lz77<T>, char: u8) -> Nullable<Span<usize>>;
    fn record_char_pos(ref self: Lz77<T>, char: u8);
    fn update_matches(ref self: Lz77<T>, ref char_pos: Span<usize>);
    fn best_match(ref self: Lz77<T>) -> Nullable<Match>;
}

impl Lz77Impl of Lz77Trait<ByteArray> {
    #[inline(always)]
    fn new(input: @ByteArray) -> Lz77<ByteArray> {
        Lz77 {
            input: input,
            output: Default::default(),
            matches: array![],
            char_pos: Default::default(),
            cur_pos: 0
        }
    }
    #[inline(always)]
    fn window_start(self: @Lz77<ByteArray>) -> usize {
        match u32_overflowing_sub(*self.cur_pos, WINDOW_SIZE) {
            Result::Ok(x) => x,
            Result::Err(x) => 0_u32,
        }
    }
    #[inline(always)]
    fn next_byte(ref self: Lz77<ByteArray>) -> Option<u8> {
        self.input.at(self.cur_pos)
    }
    #[inline(always)]
    fn increment_pos(ref self: Lz77<ByteArray>) {
        self.cur_pos += 1;
    }
    #[inline(always)]
    fn get_char_pos(ref self: Lz77<ByteArray>, char: u8) -> Nullable<Span<usize>> {
        let felt_char: felt252 = char.into();
        self.char_pos.get(felt_char)
    }
    fn record_char_pos(ref self: Lz77<ByteArray>, char: u8) {
        let felt_char: felt252 = char.into();
        let mut arr_pos: Array<usize> = array![];

        match match_nullable(self.get_char_pos(char)) {
            //unknown char
            FromNullableResult::Null(()) => {
                arr_pos = array![self.cur_pos];
            },
            //existing char record
            FromNullableResult::NotNull(span_pos) => {
                let mut span_pos = span_pos.unbox();
                let window_start = self.window_start();

                loop {
                    match span_pos.pop_front() {
                        Option::Some(pos) => {
                            let pos = *pos;
                            //dump pos if outside of window
                            if pos >= window_start {
                                arr_pos.append(pos);
                            }
                        },
                        Option::None(()) => {
                            break;
                        },
                    };
                };
                arr_pos.append(self.cur_pos);
            }
        }

        self.char_pos.insert(felt_char, nullable_from_box(BoxTrait::new(arr_pos.span())));
    }
    fn update_matches(ref self: Lz77<ByteArray>, ref char_pos: Span<usize>) {
        let mut matches: Array<Match> = array![];
        loop {
            match char_pos.pop_front() {
                Option::Some(pos) => {
                    let pos = *pos;
                    if self.matches.is_empty() {
                        'new match'.print();
                        //save new match
                        matches.append(Match { distance: self.cur_pos - pos, length: 1 })
                    } else {
                        //loop through existings matches
                        loop {
                            match self.matches.pop_front() {
                                Option::Some(m) => {
                                    if m.distance == (self.cur_pos - pos) {
                                        'updated match'.print();
                                        //update match
                                        matches
                                            .append(
                                                Match { distance: m.distance, length: m.length + 1 }
                                            );
                                    }
                                },
                                Option::None(()) => {
                                    break;
                                },
                            };
                        }
                    }
                },
                Option::None(()) => {
                    break;
                },
            };
        };

        self.matches = matches;
    }
    fn best_match(ref self: Lz77<ByteArray>) -> Nullable<Match> {
        let mut best: Nullable<Match> = Default::default();
        loop {
            match self.matches.pop_front() {
                Option::Some(m) => {
                    match match_nullable(best) {
                        FromNullableResult::Null(()) => {
                            best = nullable_from_box(BoxTrait::new(m));
                        },
                        FromNullableResult::NotNull(best_m) => {
                            if m.length > best_m.unbox().length {
                                best = nullable_from_box(BoxTrait::new(m));
                            }
                        }
                    }
                },
                Option::None(()) => {
                    break;
                },
            };
        };
        best
    }
}

impl Lz77Encoder of Encoder<ByteArray> {
    fn encode(data: ByteArray) -> ByteArray {
        let mut lz77 = Lz77Impl::new(@data);

        loop {
            //get new byte
            match lz77.next_byte() {
                Option::Some(char) => {
                    char.print();
                    match match_nullable(lz77.get_char_pos(char)) {
                        //no previous char record
                        FromNullableResult::Null(()) => {
                            //process previous matches
                            if !lz77.matches.is_empty() {
                                let best: Nullable<Match> = lz77.best_match();
                                if best.deref().length > MIN_MATCH_LEN {
                                    //append match
                                    'append match'.print();
                                } else {
                                    //append raw sequence
                                    'append raw sequence'.print();
                                }
                            }
                            //reference char position in dict
                            lz77.record_char_pos(char);
                            'new ref'.print();
                            //append raw char to output
                            lz77.output.append_byte(char);
                        },
                        //existing char records
                        FromNullableResult::NotNull(char_pos) => {
                            let mut char_pos = char_pos.unbox();
                            lz77.update_matches(ref char_pos);
                            lz77.record_char_pos(char);
                        }
                    }
                },
                // EOF
                Option::None(()) => {
                    break;
                },
            }

            lz77.increment_pos();
        };

        lz77.output
    }
}
