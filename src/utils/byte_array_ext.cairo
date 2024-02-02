use alexandria_data_structures::bit_array::BitArray;

#[generate_trait]
impl SubStrImpl of SubStrTrait {
    fn sub_str(self: @ByteArray, start: usize, length: usize) -> ByteArray {
        let self_length = self.len();
        let final_pos = start + length;
        assert(final_pos <= self_length, 'out of bound');
        let mut result: ByteArray = Default::default();
        let mut i = start;

        loop {
            if i >= final_pos {
                break;
            }

            result.append_byte(self[i]);
            i += 1;
        };

        result
    }
}

impl BitArrayIntoByteArray of Into<BitArray, ByteArray> {
    fn into(self: BitArray) -> ByteArray {
        ByteArray {
            data: self.data, pending_word: self.current, pending_word_len: (self.write_pos / 8) + 1
        }
    }
}

impl ByteArrayIntoBitArray of Into<ByteArray, BitArray> {
    fn into(self: ByteArray) -> BitArray {
        BitArray {
            data: self.data,
            current: self.pending_word,
            write_pos: self.pending_word_len * 8,
            read_pos: 0
        }
    }
}
