use compression::commons::{Encoder, Decoder};
use compression::lz77::Lz77Encoder;

use debug::PrintTrait;

impl DeflateEncoder of Encoder<ByteArray> {
    fn encode(data: ByteArray) -> ByteArray {
        let result = Lz77Encoder::encode(data);
        // Huffman codes

        result
    }
}

impl DeflateDecoder of Decoder<ByteArray> {
    fn decode(data: ByteArray) -> ByteArray {
        let mut result: ByteArray = Default::default();
        let mut pointer: usize = 0;
        // read deflate block
        let current_byte = data[pointer];
        current_byte.print();
        // 1st bit of current byte
        let last_block = current_byte & 0x1 == 0x1;
        'last_block'.print();
        last_block.print();
        // 2nd and 3th bits of current byte
        let block_mode = (current_byte & 0x6) / 0x2;
        'block_mode'.print();
        block_mode.print();
        // 2 nexts bytes
        let length: u16 = data[pointer + 1].into() * 0x100 + data[pointer + 2].into();
        'length'.print();
        length.print();
        'Nlength'.print();
        (length ^ 0xFFFF).print();
        // 2 nexts bytes
        let nlength: u16 = data[pointer + 3].into() * 0x100 + data[pointer + 4].into();
        'nlength'.print();
        nlength.print();
        //  read raw data

        result
    }
}
//bits read from byte
// (current_byte & 0x1).print();
// ((current_byte & 0x2) / 0x2).print();
// ((current_byte & 0x4) / 0x4).print();
// ((current_byte & 0x8) / 0x8).print();
// ((current_byte & 0x10) / 0x10).print();
// ((current_byte & 0x20) / 0x20).print();
// ((current_byte & 0x40) / 0x40).print();
// ((current_byte & 0x80) / 0x80).print();


