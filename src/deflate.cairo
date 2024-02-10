use compression::commons::{Encoder, Decoder};
use compression::lz77::{Lz77Encoder, Lz77Decoder, Lz77Error};
use compression::huffman::{HuffmanEncoder, HuffmanDecoder, HuffmanError};
use compression::utils::slice::{Slice, ByteArraySliceImpl, BitArraySliceImpl};
use compression::utils::bit_array_ext::{
    BitArrayImplExt, BitArrayIntoByteArray, ByteArraySliceIntoBitArray, BitArraySliceIntoByteArray
};
use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};

const MAX_BLOCK_SIZE: usize = 65536;

#[derive(Drop)]
enum DeflateError {
    NotEnoughData,
    HuffmanError: HuffmanError,
    Lz77Error: Lz77Error
}

#[derive(Copy, Drop)]
enum BlockType {
    Raw,
    StaticHuffman,
    DynamicHuffman
}

impl DeflateEncoder of Encoder<ByteArray> {
    fn encode(data: Slice<ByteArray>) -> ByteArray {
        let mut bit_stream: BitArray = Default::default();
        let data_length = data.len();
        let mut bfinal = false;
        let btype = BlockType::DynamicHuffman;

        let mut ptr = 0;
        loop {
            if bfinal == true {
                break;
            }

            let raw_block_length = if ptr + MAX_BLOCK_SIZE >= data_length {
                bfinal = true;
                data_length - ptr
            } else {
                MAX_BLOCK_SIZE
            };
            let raw_block = data.data.slice(data.start + ptr, raw_block_length);

            match btype {
                BlockType::Raw => {},
                BlockType::StaticHuffman => {},
                BlockType::DynamicHuffman => {
                    bit_stream.append_bit(bfinal);
                    bit_stream.write_word_be(2, 2);
                    let lz77 = Lz77Encoder::encode(raw_block);
                    let huffman = HuffmanEncoder::encode(lz77.slice(0, lz77.len()));
                    bit_stream.append_byte_array(@huffman);
                },
            }

            ptr = ptr + raw_block_length;
        };

        bit_stream.into()
    }
}

impl DeflateDecoder of Decoder<ByteArray, DeflateError> {
    fn decode(data: Slice<ByteArray>) -> Result<ByteArray, DeflateError> {
        let mut bit_stream: BitArray = data.into();
        let mut output: ByteArray = Default::default();
        let mut bfinal = false;

        let result = loop {
            if bfinal == true {
                break Result::Ok(());
            }

            if bit_stream.len() < 3 {
                break Result::Err(DeflateError::NotEnoughData);
            }

            bfinal = match felt252_is_zero(bit_stream.read_word_be(1).unwrap()) {
                zeroable::IsZeroResult::Zero => false,
                zeroable::IsZeroResult::NonZero(x) => true,
            };
            let btype = match bit_stream.read_word_be(2) {
                Option::Some(val) => {
                    if val == 0 {
                        BlockType::Raw
                    } else if val == 1 {
                        BlockType::StaticHuffman
                    } else if val == 2 {
                        BlockType::DynamicHuffman
                    } else {
                        BlockType::Raw
                    }
                },
                Option::None(()) => (BlockType::Raw)
            };

            match btype {
                BlockType::Raw => {},
                BlockType::StaticHuffman => {},
                BlockType::DynamicHuffman => {
                    let byte_stream: ByteArray = bit_stream
                        .slice(bit_stream.read_pos, bit_stream.len() - bit_stream.read_pos)
                        .into();
                    let huffman = HuffmanDecoder::decode(byte_stream.slice(0, byte_stream.len()));
                    if huffman.is_err() {
                        break Result::Err(DeflateError::HuffmanError(huffman.unwrap_err()));
                    }
                    let huffman = huffman.unwrap();
                    let lz77 = Lz77Decoder::decode(huffman.slice(0, huffman.len()));
                    if lz77.is_err() {
                        break Result::Err(DeflateError::Lz77Error(lz77.unwrap_err()));
                    }
                    let lz77 = lz77.unwrap();
                    output.append(@lz77);
                },
            }
        };

        if result.is_err() {
            return Result::Err(result.unwrap_err());
        }

        Result::Ok(output)
    }
}

#[inline(always)]
fn magic_array() -> Array<felt252> {
    array![16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
}
