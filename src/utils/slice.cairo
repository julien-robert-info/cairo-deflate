use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};

#[derive(Copy, Drop)]
struct Slice<T> {
    data: @T,
    start: usize,
    len: usize,
}

#[generate_trait]
impl ByteArraySliceImpl of ByteArraySliceTrait {
    #[inline(always)]
    fn slice(self: @ByteArray, start: usize, len: usize) -> Slice<ByteArray> {
        assert(self.len() >= start, 'Slice start outside array');
        assert(self.len() - start >= len, 'Slice larger than array');

        Slice { data: self, start: start, len: len }
    }
    #[inline(always)]
    fn len(self: @Slice<ByteArray>) -> usize {
        *self.len
    }
    #[inline(always)]
    fn at(self: @Slice<ByteArray>, index: usize) -> Option<u8> {
        if index >= *self.len {
            return Option::None;
        }

        (*self.data).at(index + *self.start)
    }
}

#[generate_trait]
impl BitArraySliceImpl of BitArraySliceTrait {
    #[inline(always)]
    fn slice(self: @BitArray, start: usize, len: usize) -> Slice<BitArray> {
        assert(self.len() >= start, 'Slice start outside array');
        assert(self.len() - start >= len, 'Slice larger than array');

        Slice { data: self, start: start, len: len }
    }
    #[inline(always)]
    fn len(self: @Slice<BitArray>) -> usize {
        *self.len
    }
    #[inline(always)]
    fn at(self: @Slice<BitArray>, index: usize) -> Option<bool> {
        if index >= *self.len {
            return Option::None;
        }

        (*self.data).at(index + *self.start)
    }
}

impl SliceIndexView of IndexView<Slice<ByteArray>, usize, u8> {
    #[inline(always)]
    fn index(self: @Slice<ByteArray>, index: usize) -> u8 {
        self.at(index).expect('Index out of bounds')
    }
}

