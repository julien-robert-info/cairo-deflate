use integer::u32_wide_mul;

const ASCII_NUMBER_OFFSET: u32 = 0x30;
const MSB_TO_LSB_SHIFT: u32 = 0x1000;
const BYTE_SHIFT: u32 = 0x10;
const U32_MASK: u64 = 0xFFFF;

trait Encoder<T> {
    fn encode(data: T) -> ByteArray;
}

trait Decoder<T> {
    fn decode(data: T) -> ByteArray;
}

impl NumberIntoString of Into<u32, Span<u8>> {
    fn into(self: u32) -> Span<u8> {
        let mut result: Array<u8> = array![];
        let mut self: u32 = self;

        loop {
            if self == 0 {
                break;
            }

            let byte = self / MSB_TO_LSB_SHIFT;
            if byte != 0 {
                result.append((byte + ASCII_NUMBER_OFFSET).try_into().unwrap());
            }
            self = (u32_wide_mul(self, BYTE_SHIFT) & U32_MASK).try_into().unwrap();
        };

        result.span()
    }
}

