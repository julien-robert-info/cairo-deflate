use nullable::FromNullableResult;
use integer::u32_overflowing_sub;
use compression::commons::{Encoder, Decoder};
use compression::offset_length_code::{
    ESCAPE_BYTE, CODE_BYTE_COUNT, MIN_CODE_LEN, MAX_CODE_LEN, OLCode
};

const WINDOW_SIZE: usize = 32768;

#[derive(Copy, Drop)]
struct Match {
    code: OLCode,
    pos: usize
}

#[derive(Destruct)]
struct Lz77<T> {
    input: @T,
    output: T,
    matches: Array<Match>,
    byte_pos: Felt252Dict<Nullable<Span<usize>>>,
    input_pos: usize,
    output_pos: usize
}

trait Lz77Trait<T> {
    fn new(input: @T) -> Lz77<T>;
    fn window_start(self: @Lz77<T>) -> usize;
    fn input_read(ref self: Lz77<T>) -> Option<u8>;
    fn increment_pos(ref self: Lz77<T>);
    fn get_byte_pos(ref self: Lz77<T>, byte: u8) -> Nullable<Span<usize>>;
    fn record_byte_pos(ref self: Lz77<T>, byte: u8);
    fn create_match(ref self: Lz77<T>, start: usize);
    fn update_matches(ref self: Lz77<T>, byte: u8);
    fn best_match(self: @Lz77<T>) -> Nullable<Match>;
    fn is_active_matching(self: @Lz77<T>) -> bool;
    fn process_matches(ref self: Lz77<T>);
    fn output_byte(ref self: Lz77<T>, byte: u8);
    fn output_raw_code(ref self: Lz77<T>, code: OLCode);
    fn output_code(ref self: Lz77<T>, code: OLCode);
    fn is_escaped(ref self: Lz77<T>) -> bool;
    fn read_code(ref self: Lz77<T>) -> OLCode;
    fn output_from_code(ref self: Lz77<T>, code: OLCode);
}

impl Lz77Impl of Lz77Trait<ByteArray> {
    #[inline(always)]
    fn new(input: @ByteArray) -> Lz77<ByteArray> {
        Lz77 {
            input: input,
            output: Default::default(),
            matches: array![],
            byte_pos: Default::default(),
            input_pos: 0,
            output_pos: 0
        }
    }
    #[inline(always)]
    fn window_start(self: @Lz77<ByteArray>) -> usize {
        match u32_overflowing_sub(*self.input_pos, WINDOW_SIZE) {
            Result::Ok(x) => x,
            Result::Err(x) => 0_u32,
        }
    }
    #[inline(always)]
    fn input_read(ref self: Lz77<ByteArray>) -> Option<u8> {
        self.input.at(self.input_pos)
    }
    #[inline(always)]
    fn increment_pos(ref self: Lz77<ByteArray>) {
        self.input_pos += 1;
    }
    #[inline(always)]
    fn get_byte_pos(ref self: Lz77<ByteArray>, byte: u8) -> Nullable<Span<usize>> {
        let felt_byte: felt252 = byte.into();
        self.byte_pos.get(felt_byte)
    }
    fn record_byte_pos(ref self: Lz77<ByteArray>, byte: u8) {
        let felt_byte: felt252 = byte.into();
        let mut arr_pos: Array<usize> = array![];
        let input_pos = self.input_pos;

        match match_nullable(self.get_byte_pos(byte)) {
            //unknown byte
            FromNullableResult::Null(()) => arr_pos = array![input_pos],
            //known byte
            FromNullableResult::NotNull(span_pos) => {
                let mut span_pos = span_pos.unbox();

                //deref previous pos
                loop {
                    match span_pos.pop_front() {
                        Option::Some(pos) => arr_pos.append(*pos),
                        Option::None(()) => { break; },
                    }
                };
                //append new pos
                arr_pos.append(input_pos);
            }
        }

        self.byte_pos.insert(felt_byte, nullable_from_box(BoxTrait::new(arr_pos.span())));
    }
    #[inline(always)]
    fn create_match(ref self: Lz77<ByteArray>, start: usize) {
        let m = Match {
            code: OLCode { offset: self.input_pos - start, length: 1 }, pos: self.input_pos
        };
        self.matches.append(m);
    }
    fn update_matches(ref self: Lz77<ByteArray>, byte: u8) {
        if !self.matches.is_empty() {
            let input_pos = self.input_pos;
            let output_pos = self.output_pos;
            let window_start = self.window_start();
            let mut updated_matches: Array<Match> = array![];
            let mut matches = self.matches.span();
            loop {
                match matches.pop_front() {
                    Option::Some(m) => {
                        let m = *m;
                        if input_pos - m.code.offset >= window_start {
                            let active = m.pos + 1 == input_pos;
                            let next_byte = self.input.at(m.pos - m.code.offset + 1).unwrap();
                            let updatable = next_byte == byte;
                            if active && updatable && m.code.length < MAX_CODE_LEN {
                                updated_matches
                                    .append(
                                        Match {
                                            code: OLCode {
                                                offset: m.code.offset, length: m.code.length + 1
                                            },
                                            pos: input_pos
                                        }
                                    );
                            } else {
                                updated_matches.append(m);
                            }
                        }
                    },
                    Option::None(()) => { break; },
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
                            if m.code.length >= MIN_CODE_LEN {
                                best = nullable_from_box(BoxTrait::new(m));
                            }
                        },
                        FromNullableResult::NotNull(best_m) => {
                            let best_m = best_m.unbox();
                            let longer = m.code.length > best_m.code.length;
                            let closer = m.code.length == best_m.code.length
                                && m.code.offset < best_m.code.offset;
                            if longer || closer {
                                best = nullable_from_box(BoxTrait::new(m));
                            }
                        }
                    }
                },
                Option::None(()) => { break; },
            };
        };
        best
    }
    fn is_active_matching(self: @Lz77<ByteArray>) -> bool {
        let mut matches = self.matches.span();
        let input_pos = *self.input_pos;
        loop {
            match matches.pop_front() {
                Option::Some(m) => {
                    let m = *m;
                    if m.pos == input_pos {
                        break true;
                    }
                },
                Option::None(()) => { break false; },
            };
        }
    }
    #[inline(always)]
    fn process_matches(ref self: Lz77<ByteArray>) {
        if !self.matches.is_empty() {
            let input_pos = self.input_pos;
            let output_pos = self.output_pos;
            match match_nullable(self.best_match()) {
                FromNullableResult::Null(()) => {
                    //output raw sequence
                    self
                        .output_raw_code(
                            OLCode {
                                offset: input_pos - output_pos, length: input_pos - output_pos
                            }
                        );
                },
                FromNullableResult::NotNull(best) => {
                    let best = best.unbox();
                    //output potential raw sequence before match
                    if output_pos + best.code.length < best.pos + 1 {
                        self
                            .output_raw_code(
                                OLCode {
                                    offset: input_pos - output_pos,
                                    length: best.pos + 1 - best.code.length - output_pos
                                }
                            );
                    }
                    self.output_code(best.code);
                    //output potential raw sequence after match
                    if best.pos + 1 < input_pos {
                        self
                            .output_raw_code(
                                OLCode {
                                    offset: input_pos - (best.pos + 1),
                                    length: input_pos - (best.pos + 1)
                                }
                            );
                    }
                }
            }
            //reset matches
            self.matches = array![];
        }
    }
    #[inline(always)]
    fn output_byte(ref self: Lz77<ByteArray>, byte: u8) {
        if byte == ESCAPE_BYTE {
            self.output.append_byte(ESCAPE_BYTE);
        }
        self.output.append_byte(byte);
        self.output_pos += 1;
    }
    fn output_raw_code(ref self: Lz77<ByteArray>, code: OLCode) {
        if code.length > 0 {
            match self.input.at(self.input_pos - code.offset) {
                Option::Some(byte) => {
                    self.output_byte(byte);
                    self
                        .output_raw_code(
                            code: OLCode { offset: code.offset - 1, length: code.length - 1 }
                        );
                },
                Option::None => {},
            }
        }
    }
    #[inline(always)]
    fn output_code(ref self: Lz77<ByteArray>, code: OLCode) {
        let byte_code: ByteArray = code.into();
        self.output.append(@byte_code);

        self.output_pos += code.length;
    }
    #[inline(always)]
    fn is_escaped(ref self: Lz77<ByteArray>) -> bool {
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
    fn read_code(ref self: Lz77<ByteArray>) -> OLCode {
        let byte_left = self.input.len() - self.input_pos;
        assert(byte_left >= CODE_BYTE_COUNT, 'Not enougth bytes to read');
        self.increment_pos();
        let length: usize = self.input_read().unwrap().into() + MIN_CODE_LEN;
        self.increment_pos();
        let mut offset: usize = self.input_read().unwrap().into();
        self.increment_pos();
        offset = offset * 256 + self.input_read().unwrap().into();

        OLCode { length: length, offset: offset }
    }
    fn output_from_code(ref self: Lz77<ByteArray>, code: OLCode) {
        if code.length > 0 {
            match self.output.at(self.output_pos - code.offset) {
                Option::Some(byte) => {
                    self.output_byte(byte);
                    self
                        .output_from_code(
                            code: OLCode { length: code.length - 1, offset: code.offset }
                        );
                },
                Option::None => {},
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
                Option::Some(byte) => {
                    lz77.update_matches(byte);
                    if !lz77.is_active_matching() {
                        lz77.process_matches();
                    }
                    match match_nullable(lz77.get_byte_pos(byte)) {
                        //no previous byte record
                        FromNullableResult::Null(()) => {
                            //output raw byte
                            lz77.output_byte(byte);
                        },
                        //existing byte records
                        FromNullableResult::NotNull(byte_pos) => {
                            let mut byte_pos = byte_pos.unbox();
                            // create new matches
                            loop {
                                match byte_pos.pop_front() {
                                    Option::Some(pos) => { lz77.create_match(*pos); },
                                    Option::None(()) => { break; },
                                };
                            };
                        }
                    }
                    //reference byte position in dict
                    lz77.record_byte_pos(byte);
                    lz77.increment_pos();
                },
                Option::None(()) => { break; },
            };
        };

        lz77.output
    }
}

impl Lz77Decoder of Decoder<ByteArray> {
    fn decode(data: ByteArray) -> ByteArray {
        let mut lz77 = Lz77Impl::new(@data);

        loop {
            match lz77.input_read() {
                Option::Some(byte) => {
                    if byte == ESCAPE_BYTE {
                        if lz77.is_escaped() {
                            lz77.increment_pos();
                            lz77.output_byte(byte);
                        } else {
                            lz77.output_from_code(lz77.read_code());
                        }
                    } else {
                        lz77.output_byte(byte);
                    }
                },
                Option::None => { break; },
            }
            lz77.increment_pos();
        };

        lz77.output
    }
}
