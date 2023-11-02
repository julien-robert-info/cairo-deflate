use nullable::FromNullableResult;
use dict::Felt252DictTrait;
use integer::u32_overflowing_sub;
use compression::commons::{Encoder, NumberIntoString};

use debug::PrintTrait;

const WINDOW_SIZE: usize = 32768;
const MIN_MATCH_LEN: usize = 3;

#[derive(Copy, Drop)]
struct Match {
    start: usize,
    length: usize,
    pos: usize
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
    fn input_read(ref self: Lz77<T>) -> Option<u8>;
    fn output_pos(ref self: Lz77<T>) -> usize;
    fn increment_pos(ref self: Lz77<T>);
    fn get_char_pos(ref self: Lz77<T>, char: u8) -> Nullable<Span<usize>>;
    fn record_char_pos(ref self: Lz77<T>, char: u8);
    fn create_match(ref self: Lz77<T>, start: usize);
    fn update_matches(ref self: Lz77<T>, char: u8);
    fn best_match(self: @Lz77<T>) -> Nullable<Match>;
    fn active_matching(self: @Lz77<T>) -> bool;
    fn output_raw_match(ref self: Lz77<T>, m: Match);
    fn process_matches(ref self: Lz77<T>);
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
    fn input_read(ref self: Lz77<ByteArray>) -> Option<u8> {
        self.input.at(self.cur_pos)
    }
    #[inline(always)]
    fn output_pos(ref self: Lz77<ByteArray>) -> usize {
        self.output.len()
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
            FromNullableResult::Null(()) => {
                arr_pos = array![self.cur_pos];
            },
            FromNullableResult::NotNull(span_pos) => {
                let mut span_pos = span_pos.unbox();
                let window_start = self.window_start();

                loop {
                    match span_pos.pop_front() {
                        Option::Some(pos) => {
                            let pos = *pos;
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
    #[inline(always)]
    fn create_match(ref self: Lz77<ByteArray>, start: usize) {
        let m = Match { start: start, length: 1, pos: self.cur_pos };
        self.matches.append(m);
    }
    fn update_matches(ref self: Lz77<ByteArray>, char: u8) {
        if !self.matches.is_empty() {
            let cur_pos = self.cur_pos;
            // 'cur_pos'.print();
            // cur_pos.print();
            // let output_pos = self.output_pos();
            // 'output_pos'.print();
            // output_pos.print();
            let mut updated_matches: Array<Match> = array![];
            let mut matches = self.matches.span();
            loop {
                match matches.pop_front() {
                    Option::Some(m) => {
                        let m = *m;
                        let active = m.pos + 1 == cur_pos;
                        let next_pos = m.start + m.length;
                        let next_char = self.input.at(next_pos).unwrap();
                        let updatable = next_char == char;
                        if active && updatable {
                            // 'updated'.print();
                            updated_matches
                                .append(
                                    Match { start: m.start, length: m.length + 1, pos: cur_pos }
                                );
                        } else {
                            // 'not updated'.print();
                            // 'match'.print();
                            // m.start.print();
                            // m.length.print();
                            // m.pos.print();
                            // 'active'.print();
                            // active.print();
                            // 'updatable'.print();
                            // updatable.print();
                            // 'next_char'.print();
                            // next_char.print();
                            updated_matches.append(m);
                        }
                    },
                    Option::None(()) => {
                        break;
                    },
                };
            };

            self.matches = updated_matches;
        }
    }
    fn best_match(self: @Lz77<ByteArray>) -> Nullable<Match> {
        let mut best: Nullable<Match> = Default::default();
        let mut matches = self.matches.span();
        loop {
            match matches.pop_front() {
                Option::Some(m) => {
                    let m = *m;
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
    fn active_matching(self: @Lz77<ByteArray>) -> bool {
        let mut matches = self.matches.span();
        let cur_pos = *self.cur_pos;
        // 'active_matching'.print();
        // cur_pos.print();
        loop {
            match matches.pop_front() {
                Option::Some(m) => {
                    let m = *m;
                    // 'match'.print();
                    // m.start.print();
                    // m.length.print();
                    // m.pos.print();
                    if m.pos == cur_pos {
                        break true;
                    }
                },
                Option::None(()) => {
                    break false;
                },
            };
        }
    }
    fn output_raw_match(ref self: Lz77<ByteArray>, m: Match) {
        if m.length > 0 {
            match self.input.at(m.start) {
                Option::Some(char) => {
                    self.output.append_byte(char);
                    self
                        .output_raw_match(
                            Match { start: m.start + 1, length: m.length - 1, pos: m.pos }
                        );
                },
                Option::None => {},
            }
        }
    }
    fn process_matches(ref self: Lz77<ByteArray>) {
        if !self.matches.is_empty() {
            // 'matches'.print();
            // self.matches.len().print();
            let best: Match = self.best_match().deref();
            // 'best match'.print();
            // best.distance.print();
            // best.start.print();
            // best.length.print();
            if best.length > MIN_MATCH_LEN {
                //append match
                'append match'.print();
                let mut distance: Span<u8> = (self.output.len() - best.start).into();
                let mut length: Span<u8> = best.length.into();
                self.output.append_byte('<');
                loop {
                    match distance.pop_front() {
                        Option::Some(byte) => {
                            self.output.append_byte(*byte);
                        },
                        Option::None => {
                            break false;
                        },
                    };
                };
                self.output.append_byte(',');
                loop {
                    match length.pop_front() {
                        Option::Some(byte) => {
                            self.output.append_byte(*byte);
                        },
                        Option::None => {
                            break false;
                        },
                    };
                };
                self.output.append_byte('>');
            } else {
                //append raw sequence
                self.output_raw_match(best);
            }
        }
    }
}

impl Lz77Encoder of Encoder<ByteArray> {
    fn encode(data: ByteArray) -> ByteArray {
        let mut lz77 = Lz77Impl::new(@data);

        loop {
            //get new byte
            match lz77.input_read() {
                Option::Some(char) => {
                    char.print();
                    lz77.update_matches(char);
                    if !lz77.active_matching() {
                        lz77.process_matches();
                    }
                    match match_nullable(lz77.get_char_pos(char)) {
                        //no previous char record
                        FromNullableResult::Null(()) => {
                            //append raw char to output
                            lz77.output.append_byte(char);
                        },
                        //existing char records
                        FromNullableResult::NotNull(char_pos) => {
                            let char_pos = char_pos.unbox();
                            // create new match
                            lz77.create_match(*char_pos.get(char_pos.len() - 1).unwrap().unbox());
                        }
                    }
                    //reference char position in dict
                    lz77.record_char_pos(char);
                },
                Option::None(()) => {
                    break;
                },
            }

            lz77.increment_pos();
        };

        'output'.print();
        let output = lz77.output.clone();
        let mut i = 0;
        loop {
            match output.at(i) {
                Option::Some(char) => {
                    char.print();
                    i += 1;
                },
                Option::None(()) => {
                    break;
                },
            };
        };
        lz77.output
    }
}
