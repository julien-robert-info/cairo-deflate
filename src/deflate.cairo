use compression::encoder::{Encoder, Decoder};
use compression::lz77::{Lz77Encoder, Lz77EncoderOptions, Lz77Decoder, Lz77Error};
use compression::huffman::{HuffmanEncoder, HuffmanEncoderOptions, HuffmanDecoder, HuffmanError};
use compression::utils::slice::{Slice, ByteArraySliceImpl, BitArraySliceImpl};
use compression::utils::bit_array_ext::{
    BitArrayImplExt, BitArrayIntoByteArray, ByteArraySliceIntoBitArray, BitArraySliceIntoByteArray
};
use alexandria_data_structures::bit_array::{BitArray, BitArrayImpl};

#[derive(Copy, Drop)]
struct DeflateEncoderOptions {
    max_block_size: usize,
    block_type: BlockType,
    lz77_options: Lz77EncoderOptions,
}

impl DeflateEncoderOptionsDefault of Default<DeflateEncoderOptions> {
    #[inline(always)]
    fn default() -> DeflateEncoderOptions {
        DeflateEncoderOptions {
            max_block_size: 65536,
            block_type: BlockType::DynamicHuffman,
            lz77_options: Default::default()
        }
    }
}

#[derive(Drop)]
enum DeflateError {
    InconsistantData,
    NotEnoughData,
    WrongBlockType,
    HuffmanError: HuffmanError,
    Lz77Error: Lz77Error
}

#[derive(Copy, Drop)]
enum BlockType {
    Raw,
    StaticHuffman,
    DynamicHuffman,
    Reserved
}

impl DeflateEncoder of Encoder<ByteArray, DeflateEncoderOptions> {
    fn encode(data: Slice<ByteArray>, options: DeflateEncoderOptions) -> ByteArray {
        let mut bit_stream: BitArray = Default::default();
        let data_length = data.len();
        let mut bfinal = false;
        let btype = options.block_type;

        let mut ptr = 0;
        loop {
            if bfinal {
                break;
            }

            let raw_block_length = if ptr + options.max_block_size >= data_length {
                bfinal = true;
                data_length - ptr
            } else {
                options.max_block_size
            };
            let raw_block = data.data.slice(data.start + ptr, raw_block_length);

            match btype {
                BlockType::Raw => {
                    bit_stream.append_bit(bfinal);
                    bit_stream.write_word_be(0, 2);
                    bit_stream.write_word_be(0, 5);
                    bit_stream.write_word_be(raw_block_length.into(), 16);
                    bit_stream.write_word_be((~raw_block_length).into(), 16);
                    let mut i = 0;
                    loop {
                        if i >= raw_block.data.data.len() {
                            bit_stream
                                .write_word_be(
                                    *raw_block.data.pending_word,
                                    *raw_block.data.pending_word_len * 8
                                );
                            break;
                        }
                        bit_stream.write_word_be((*raw_block.data.data.at(i)).into(), 248);
                        i += 1;
                    }
                },
                BlockType::StaticHuffman => {
                    bit_stream.append_bit(bfinal);
                    bit_stream.write_word_be(2, 2);
                    let lz77 = Lz77Encoder::encode(raw_block, options.lz77_options);
                    let huffman = HuffmanEncoder::encode(
                        lz77.slice(0, lz77.len()), HuffmanEncoderOptions { huffman_dynamic: false }
                    );
                    bit_stream.append_byte_array(@huffman);
                },
                BlockType::DynamicHuffman => {
                    bit_stream.append_bit(bfinal);
                    bit_stream.write_word_be(2, 2);
                    let lz77 = Lz77Encoder::encode(raw_block, options.lz77_options);
                    let huffman = HuffmanEncoder::encode(
                        lz77.slice(0, lz77.len()), HuffmanEncoderOptions { huffman_dynamic: true }
                    );
                    bit_stream.append_byte_array(@huffman);
                },
                BlockType::Reserved => {},
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
            if bfinal {
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
                        BlockType::Reserved
                    }
                },
                Option::None(()) => (BlockType::Reserved)
            };

            match btype {
                BlockType::Raw => {
                    let ignored = bit_stream.read_word_be(5);
                    if ignored.is_none() {
                        break Result::Err(DeflateError::NotEnoughData);
                    }
                    let len = bit_stream.read_word_be(16);
                    if len.is_none() {
                        break Result::Err(DeflateError::NotEnoughData);
                    }
                    let len: u16 = len.unwrap().try_into().unwrap();
                    let nlen = bit_stream.read_word_be(16);
                    if nlen.is_none() {
                        break Result::Err(DeflateError::NotEnoughData);
                    }
                    let nlen: u16 = nlen.unwrap().try_into().unwrap();

                    if ~len != nlen {
                        break Result::Err(DeflateError::InconsistantData);
                    }
                    let mut i = 0;
                    loop {
                        if i >= len {
                            break Result::Ok(());
                        }
                        let byte = bit_stream.read_word_be(8);
                        if byte.is_none() {
                            break Result::Err(DeflateError::NotEnoughData);
                        }
                        output.append_byte(byte.unwrap().try_into().unwrap());

                        i += 1;
                    }
                },
                BlockType::StaticHuffman => {
                    let byte_stream: ByteArray = bit_stream
                        .slice(bit_stream.read_pos, bit_stream.len() - bit_stream.read_pos)
                        .into();
                    let huffman = HuffmanDecoder::decode(
                        byte_stream.slice(0, byte_stream.len()),
                        HuffmanEncoderOptions { huffman_dynamic: false }
                    );
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

                    break Result::Ok(());
                },
                BlockType::DynamicHuffman => {
                    let byte_stream: ByteArray = bit_stream
                        .slice(bit_stream.read_pos, bit_stream.len() - bit_stream.read_pos)
                        .into();
                    let huffman = HuffmanDecoder::decode(
                        byte_stream.slice(0, byte_stream.len()),
                        HuffmanEncoderOptions { huffman_dynamic: true }
                    );
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

                    break Result::Ok(());
                },
                BlockType::Reserved => { break Result::Err(DeflateError::WrongBlockType); },
            };
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
