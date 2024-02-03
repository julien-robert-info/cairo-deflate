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
