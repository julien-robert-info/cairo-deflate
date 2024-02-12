use nullable::FromNullableResult;
use integer::u32_overflowing_sub;
use compression::encoder::{Encoder, Decoder};
use compression::sequence::{
    ESCAPE_BYTE, SEQUENCE_BYTE_COUNT, MIN_SEQUENCE_LEN, MAX_SEQUENCE_LEN, Sequence
};
use compression::utils::slice::{Slice, ByteArraySliceImpl};
use alexandria_data_structures::array_ext::SpanTraitExt;

#[derive(Copy, Drop)]
struct Lz77EncoderOptions {
    window_size: usize
}

impl Lz77EncoderOptionsDefault of Default<Lz77EncoderOptions> {
    #[inline(always)]
    fn default() -> Lz77EncoderOptions {
        Lz77EncoderOptions { window_size: 32768 }
    }
}

#[derive(Copy, Drop)]
struct Match {
    sequence: Sequence,
    pos: usize
}

#[derive(Destruct)]
struct Lz77<T> {
    window_size: usize,
    input: @Slice<T>,
    output: T,
    matches: Array<Match>,
    byte_pos: Felt252Dict<Nullable<Span<usize>>>,
    input_pos: usize,
    output_pos: usize
}

#[derive(Drop)]
enum Lz77Error {
    NotEnoughData
}

trait Lz77Trait<T> {
    fn new(input: @Slice<T>, options: Lz77EncoderOptions) -> Lz77<T>;
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
    fn output_raw_sequence(ref self: Lz77<T>, sequence: Sequence);
    fn output_sequence(ref self: Lz77<T>, sequence: Sequence);
    fn is_escaped(ref self: Lz77<T>) -> bool;
    fn read_sequence(ref self: Lz77<T>) -> Result<Sequence, Lz77Error>;
    fn output_from_sequence(ref self: Lz77<T>, sequence: Sequence);
}

impl Lz77Impl of Lz77Trait<ByteArray> {
    #[inline(always)]
    fn new(input: @Slice<ByteArray>, options: Lz77EncoderOptions) -> Lz77<ByteArray> {
        Lz77 {
            window_size: options.window_size,
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
        match u32_overflowing_sub(*self.input_pos, *self.window_size) {
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
                arr_pos = span_pos.unbox().dedup();
                arr_pos.append(input_pos);
            }
        }

        self.byte_pos.insert(felt_byte, nullable_from_box(BoxTrait::new(arr_pos.span())));
    }
    #[inline(always)]
    fn create_match(ref self: Lz77<ByteArray>, start: usize) {
        let m = Match {
            sequence: Sequence { distance: self.input_pos - start, length: 1 }, pos: self.input_pos
        };
        self.matches.append(m);
    }
    fn update_matches(ref self: Lz77<ByteArray>, byte: u8) {
        if !self.matches.is_empty() {
            let input_pos = self.input_pos;
            let window_start = self.window_start();
            let mut updated_matches: Array<Match> = array![];
            let mut matches = self.matches.span();
            loop {
                match matches.pop_front() {
                    Option::Some(m) => {
                        let m = *m;
                        if input_pos - m.sequence.distance >= window_start {
                            let active = m.pos + 1 == input_pos;
                            let next_byte = self.input.at(m.pos - m.sequence.distance + 1).unwrap();
                            let updatable = next_byte == byte;
                            if active && updatable && m.sequence.length < MAX_SEQUENCE_LEN {
                                updated_matches
                                    .append(
                                        Match {
                                            sequence: Sequence {
                                                distance: m.sequence.distance,
                                                length: m.sequence.length + 1
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
                            if m.sequence.length >= MIN_SEQUENCE_LEN {
                                best = nullable_from_box(BoxTrait::new(m));
                            }
                        },
                        FromNullableResult::NotNull(best_m) => {
                            let best_m = best_m.unbox();
                            let longer = m.sequence.length > best_m.sequence.length;
                            let closer = m.sequence.length == best_m.sequence.length
                                && m.sequence.distance < best_m.sequence.distance;
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
                        .output_raw_sequence(
                            Sequence {
                                distance: input_pos - output_pos, length: input_pos - output_pos
                            }
                        );
                },
                FromNullableResult::NotNull(best) => {
                    let best = best.unbox();
                    //output potential raw sequence before match
                    if output_pos + best.sequence.length < best.pos + 1 {
                        self
                            .output_raw_sequence(
                                Sequence {
                                    distance: input_pos - output_pos,
                                    length: best.pos + 1 - best.sequence.length - output_pos
                                }
                            );
                    }
                    self.output_sequence(best.sequence);
                    //output potential raw sequence after match
                    if best.pos + 1 < input_pos {
                        self
                            .output_raw_sequence(
                                Sequence {
                                    distance: input_pos - (best.pos + 1),
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
    fn output_raw_sequence(ref self: Lz77<ByteArray>, sequence: Sequence) {
        if sequence.length > 0 {
            match self.input.at(self.input_pos - sequence.distance) {
                Option::Some(byte) => {
                    self.output_byte(byte);
                    self
                        .output_raw_sequence(
                            sequence: Sequence {
                                distance: sequence.distance - 1, length: sequence.length - 1
                            }
                        );
                },
                Option::None => {},
            }
        }
    }
    #[inline(always)]
    fn output_sequence(ref self: Lz77<ByteArray>, sequence: Sequence) {
        let byte_sequence: ByteArray = sequence.into();
        self.output.append(@byte_sequence);

        self.output_pos += sequence.length;
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
    fn read_sequence(ref self: Lz77<ByteArray>) -> Result<Sequence, Lz77Error> {
        let byte_left = self.input.len() - self.input_pos;
        if byte_left < SEQUENCE_BYTE_COUNT {
            return Result::Err(Lz77Error::NotEnoughData);
        }

        self.increment_pos();
        let length: u32 = self.input_read().unwrap().into() + MIN_SEQUENCE_LEN;
        self.increment_pos();
        let mut distance: u32 = self.input_read().unwrap().into();
        self.increment_pos();
        distance = distance * 256 + self.input_read().unwrap().into();

        Result::Ok(Sequence { length: length, distance: distance })
    }
    fn output_from_sequence(ref self: Lz77<ByteArray>, sequence: Sequence) {
        if sequence.length > 0 {
            match self.output.at(self.output_pos - sequence.distance) {
                Option::Some(byte) => {
                    self.output_byte(byte);
                    self
                        .output_from_sequence(
                            sequence: Sequence {
                                length: sequence.length - 1, distance: sequence.distance
                            }
                        );
                },
                Option::None => {},
            }
        }
    }
}

impl Lz77Encoder of Encoder<ByteArray, Lz77EncoderOptions> {
    fn encode(data: Slice<ByteArray>, options: Lz77EncoderOptions) -> ByteArray {
        let mut lz77 = Lz77Impl::new(@data, options);

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

impl Lz77Decoder of Decoder<ByteArray, Lz77Error> {
    fn decode(data: Slice<ByteArray>) -> Result<ByteArray, Lz77Error> {
        let mut lz77 = Lz77Impl::new(@data, Default::default());

        let result = loop {
            match lz77.input_read() {
                Option::Some(byte) => {
                    if byte == ESCAPE_BYTE {
                        if lz77.is_escaped() {
                            lz77.increment_pos();
                            lz77.output_byte(byte);
                        } else {
                            let result = lz77.read_sequence();
                            match result {
                                Result::Ok(sequence) => lz77.output_from_sequence(sequence),
                                Result::Err(err) => { break Result::Err(err); }
                            }
                        }
                    } else {
                        lz77.output_byte(byte);
                    }
                },
                Option::None => { break Result::Ok(()); },
            }
            lz77.increment_pos();
        };

        match result {
            Result::Ok(()) => Result::Ok(lz77.output),
            Result::Err(err) => Result::Err(err)
        }
    }
}
