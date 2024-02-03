use bytes_31::{BYTES_IN_BYTES31, POW_2_8};
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
        let mut current: u256 = self.current.into();
        loop {
            if shift == 0 {
                break;
            }
            current = current / POW_2_8.into();
            shift -= 1;
        };

        ByteArray {
            data: self.data,
            pending_word: current.try_into().unwrap(),
            pending_word_len: pending_word_len
        }
    }
}

impl ByteArrayIntoBitArray of Into<ByteArray, BitArray> {
    fn into(self: ByteArray) -> BitArray {
        let data_len = self.data.len();
        let pending_word_len = self.pending_word_len;
        let mut shift = BYTES_IN_BYTES31 - pending_word_len;
        let mut current: u256 = self.pending_word.into();
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
