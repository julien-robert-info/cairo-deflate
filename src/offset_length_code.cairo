const ESCAPE_BYTE: u8 = 0xFF;
const CODE_BYTE_COUNT: usize = 3;
const MIN_CODE_LEN: usize = 3;
const MAX_CODE_LEN: usize = 257;

#[derive(Copy, Drop)]
struct OLCode {
    offset: usize,
    length: usize
}

//format: ESCAPE_BYTE then 1 length byte then 2 offset bytes
impl OLCodeIntoBytesArray of Into<OLCode, ByteArray> {
    #[inline(always)]
    fn into(self: OLCode) -> ByteArray {
        let length = self.length - MIN_CODE_LEN;
        let offset = self.offset;
        let mut result: ByteArray = Default::default();
        result.append_byte(ESCAPE_BYTE);
        result.append_byte(length.try_into().unwrap());
        result.append_byte(((offset & 0xFF00) / 0x100).try_into().unwrap());
        result.append_byte((offset & 0xFF).try_into().unwrap());

        result
    }
}
