use bytes_31::{BYTES_IN_BYTES31, POW_2_8};
use traits::DivRem;
use compression::utils::slice::{Slice, ByteArraySliceImpl, BitArraySliceImpl};
use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};
use alexandria_math::{pow, BitShift};

#[generate_trait]
impl BitArrayImplExt of BitArrayTraitExt {
    fn append_byte_array(ref self: BitArray, byte_array: @ByteArray) {
        let mut i = 0;
        loop {
            match byte_array.at(i) {
                Option::Some(byte) => { self.write_word_be(byte.into(), 8); },
                Option::None => { break; }
            };

            i += 1;
        };
    }
}

impl BitArrayIntoByteArray of Into<BitArray, ByteArray> {
    fn into(self: BitArray) -> ByteArray {
        let pending_word_len = ((self.write_pos % 248) / 8) + 1;
        let mut shift = BYTES_IN_BYTES31 - pending_word_len;
        let mut pending_word: u256 = self.current.into();
        pending_word = pending_word / pow(POW_2_8.into(), shift.into());

        ByteArray {
            data: self.data,
            pending_word: pending_word.try_into().unwrap(),
            pending_word_len: pending_word_len
        }
    }
}

impl ByteArraySliceIntoBitArray of Into<Slice<ByteArray>, BitArray> {
    fn into(self: Slice<ByteArray>) -> BitArray {
        let mut result: BitArray = Default::default();

        let mut span = self.data.data.span();
        loop {
            match span.pop_front() {
                Option::Some(word) => { result.data.append(*word); },
                Option::None => { break; },
            }
        };

        let mut shift = BYTES_IN_BYTES31 - *self.data.pending_word_len;
        let mut current: u256 = (*self.data.pending_word).into();
        current = current * pow(POW_2_8.into(), shift.into());

        result.current = current.try_into().unwrap();
        result.read_pos = self.start * 8;
        result.write_pos = result.read_pos + self.len * 8;

        result
    }
}

impl BitArraySliceIntoByteArray of Into<Slice<BitArray>, ByteArray> {
    fn into(self: Slice<BitArray>) -> ByteArray {
        let mut result: ByteArray = Default::default();
        result.pending_word_len = ((self.len % 248) / 8) + 1;

        let (byte, bit) = DivRem::div_rem(self.start, 8_usize.try_into().unwrap());
        let (word, byte) = DivRem::div_rem(byte, BYTES_IN_BYTES31.try_into().unwrap());

        let mut span = self.data.data.span();
        let mut i = 0;
        loop {
            if i >= word {
                break;
            }
            span.pop_front();
            i += 1;
        };

        let shift = byte * 8 + bit;
        if shift == 0 {
            loop {
                match span.pop_front() {
                    Option::Some(word) => { result.data.append(*word); },
                    Option::None => {
                        let mut pending_word_shift = BYTES_IN_BYTES31 - result.pending_word_len;
                        let mut pending_word: u256 = (*self.data.current).into();
                        pending_word = pending_word
                            / pow(POW_2_8.into(), pending_word_shift.into());
                        result.pending_word = pending_word.try_into().unwrap();

                        break;
                    },
                }
            };
        } else {
            let mut mask = 0;
            i = 0;
            loop {
                if i.into() >= shift {
                    break;
                }
                mask = (mask * 2) + 1;

                i += 1;
            };

            let inv_shift = 248 - shift;
            mask = BitShift::shl(mask, inv_shift.into());
            let mut current_word = 0;
            let span_len = span.len();
            loop {
                match span.pop_front() {
                    Option::Some(word) => {
                        let word: u256 = (*word).into();
                        let word_low = BitShift::shl(word & ~mask, shift.into());
                        let word_high = BitShift::shr(word & mask, inv_shift.into());
                        if span.len() < span_len - 1 {
                            current_word = current_word + word_high;
                            let current: felt252 = current_word.try_into().unwrap();
                            result.data.append(current.try_into().unwrap());
                        }
                        current_word = word_low;
                    },
                    Option::None => {
                        let mut pending_word_shift = BYTES_IN_BYTES31 - result.pending_word_len;
                        let pending_word: u256 = (*self.data.current).into();
                        let mut pending_low = BitShift::shl(pending_word & ~mask, shift.into());
                        let pending_high = BitShift::shr(pending_word & mask, inv_shift.into());

                        current_word = current_word + pending_high;
                        let current: felt252 = current_word.try_into().unwrap();
                        result.data.append(current.try_into().unwrap());

                        pending_low = pending_low / pow(POW_2_8.into(), pending_word_shift.into());
                        result.pending_word = pending_low.try_into().unwrap();

                        break;
                    },
                }
            };
        }

        result
    }
}

