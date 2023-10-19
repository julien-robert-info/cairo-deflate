use nullable::FromNullableResult;
use dict::{Felt252DictTrait, Felt252DictEntryTrait};
use integer::u32_overflowing_sub;
use compression::commons::Encoder;

use debug::PrintTrait;

const WINDOW_SIZE: usize = 32768;
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
    fn input_read(ref self: Lz77<T>) -> Option<u8>;
    fn increment_pos(ref self: Lz77<T>);
    fn get_char_pos(ref self: Lz77<T>, char: u8) -> Nullable<Span<usize>>;
    fn record_char_pos(ref self: Lz77<T>, char: u8);
    fn update_matches(ref self: Lz77<T>, char_pos: Span<usize>);
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
    fn update_matches(ref self: Lz77<ByteArray>, char_pos: Span<usize>) {
        let mut updated_matches: Array<Match> = array![];
        let mut char_pos = char_pos;
        let cur_pos = self.cur_pos;
        'match update'.print();
        'cur_pos'.print();
        cur_pos.print();
        loop {
            match char_pos.pop_front() {
                Option::Some(pos) => {
                    let pos = *pos;
                    'pos'.print();
                    pos.print();
                    let mut correponding_match_found = false;
                    let mut matches = self.matches.span();
                    loop {
                        match matches.pop_front() {
                            Option::Some(m) => {
                                let m = *m;
                                'match'.print();
                                m.distance.print();
                                m.length.print();
                                if cur_pos - m.distance + m.length - 1 == pos {
                                    correponding_match_found = true;
                                    let updated_m = Match {
                                        distance: m.distance + 1, length: m.length + 1
                                    };
                                    'updated match'.print();
                                    updated_m.distance.print();
                                    updated_m.length.print();
                                    updated_matches.append(updated_m);
                                }
                            },
                            Option::None(()) => {
                                break;
                            },
                        };
                    };
                    if !correponding_match_found {
                        'new match'.print();
                        (cur_pos - pos).print();
                        //save new match
                        updated_matches.append(Match { distance: cur_pos - pos, length: 1 })
                    }
                },
                Option::None(()) => {
                    break;
                },
            };
        };

        self.matches = updated_matches;
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
                    // 'distance'.print();
                    // (*m).distance.print();
                    if *m.distance + 2 == cur_pos {
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
            match self.input.at(self.cur_pos - m.distance) {
                Option::Some(char) => {
                    self.output.append_byte(char);
                    self.output_raw_match(Match { distance: m.distance - 1, length: m.length - 1 });
                },
                Option::None => {},
            }
        }
    }
    #[inline(always)]
    fn process_matches(ref self: Lz77<ByteArray>) {
        if !self.matches.is_empty() {
            'matches'.print();
            self.matches.len().print();
            let best: Match = self.best_match().deref();
            'best match'.print();
            best.distance.print();
            best.length.print();
            if best.length > MIN_MATCH_LEN {
                //append match
                'append match'.print();
            } else {
                //append raw sequence
                'append raw sequence'.print();
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
                    //process_matches if no active matching
                    if !lz77.active_matching() {
                        lz77.process_matches();
                    } else {
                        'active_matching'.print();
                    }
                    match match_nullable(lz77.get_char_pos(char)) {
                        //no previous char record
                        FromNullableResult::Null(()) => {
                            //reference char position in dict
                            lz77.record_char_pos(char);
                            //append raw char to output
                            lz77.output.append_byte(char);
                        },
                        //existing char records
                        FromNullableResult::NotNull(char_pos) => {
                            lz77.update_matches(char_pos.unbox());
                            lz77.record_char_pos(char);
                        }
                    }
                },
                Option::None(()) => {
                    break;
                },
            }

            lz77.increment_pos();
        };

        lz77.output
    }
}
