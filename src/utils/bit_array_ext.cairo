use bytes_31::{BYTES_IN_BYTES31, POW_2_8};
use compression::utils::slice::{Slice, ByteArraySliceImpl, BitArraySliceImpl};
use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};
use alexandria_math::pow;

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
        loop {
            if shift == 0 {
                break;
            }
            current = current * POW_2_8.into();
            shift -= 1;
        };

        BitArray {
            data: self.data,
            current: current.try_into().unwrap(),
            write_pos: (data_len * 248) + (pending_word_len * 8),
            read_pos: 0
        }
    }
}
