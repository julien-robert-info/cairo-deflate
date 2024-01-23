const ESCAPE_BYTE: u8 = 0xFF;
const CODE_BYTE_COUNT: usize = 3;
const MIN_CODE_LEN: u32 = 3;
const MAX_CODE_LEN: u32 = 257;

#[derive(Copy, Drop)]
struct OLCode {
    offset: u32,
    length: u32
}

#[derive(Copy, Drop)]
struct ExtraBits {
    value: felt252,
    bits: u32
}

#[generate_trait]
impl OLCodeImpl of OLCodeTrait {
    fn get_length_code(self: @OLCode) -> (felt252, ExtraBits) {
        let mut i = 0;
        let length_codes = @OLCodeImpl::_length_codes();
        let extra_bits = @OLCodeImpl::_length_extra_bits();
        loop {
            if *self.length < *length_codes[i] {
                break;
            }
            i += 1;
        };

        (
            (i + MAX_CODE_LEN).into(),
            ExtraBits { value: (*self.length - *length_codes[i - 1]).into(), bits: *extra_bits[i] }
        )
    }
    fn get_offset_code(self: @OLCode) -> (felt252, ExtraBits) {
        let mut i = 0;
        let offset_codes = @OLCodeImpl::_offset_codes();
        let extra_bits = @OLCodeImpl::_length_extra_bits();
        loop {
            if *self.offset < *offset_codes[i] {
                break;
            }
            i += 1;
        };

        (
            i.into(),
            ExtraBits { value: (*self.offset - *offset_codes[i - 1]).into(), bits: *extra_bits[i] }
        )
    }
    #[inline(always)]
    fn _length_codes() -> Array<u32> {
        array![
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            10,
            12,
            14,
            16,
            20,
            24,
            28,
            32,
            40,
            48,
            56,
            64,
            80,
            96,
            112,
            128,
            160,
            192,
            224,
            254,
            255
        ]
    }
    #[inline(always)]
    fn _length_extra_bits() -> Array<u32> {
        array![
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
        ]
    }
    #[inline(always)]
    fn _offset_codes() -> Array<u32> {
        array![
            2,
            3,
            4,
            5,
            7,
            9,
            13,
            17,
            25,
            33,
            49,
            65,
            97,
            129,
            193,
            257,
            385,
            513,
            769,
            1025,
            1537,
            2049,
            3073,
            4097,
            6145,
            8193,
            12289,
            16385,
            24577,
            32769
        ]
    }
    #[inline(always)]
    fn _offset_extra_bits() -> Array<u32> {
        array![
            0,
            0,
            0,
            1,
            1,
            2,
            2,
            3,
            3,
            4,
            4,
            5,
            5,
            6,
            6,
            7,
            7,
            8,
            8,
            9,
            9,
            10,
            10,
            11,
            11,
            12,
            12,
            13,
            13
        ]
    }
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
