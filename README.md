DEFLATE algorithm implemented in Cairo V1

## Features

-   LZ77: lazy loading, customizable window size
-   Huffman: static and dynamic tables
-   Deflate: customisable block size

## Getting Started

Add the following line to your `Scarb.toml`:

```toml
[dependencies]
compression = { git = "https://github.com/julien-robert-info/cairo-deflate.git" }
```

## Exemple

### Encode

```rust
use compression::deflate::DeflateEncoder;
use compression::utils::slice::ByteArraySliceImpl;

let mut input: ByteArray = Default::default();
input.append_word('Lorem ipsum dolor sit amet, con', 31);
input.append_word('sectetur adipiscing elit, sed d', 31);
input.append_word('o eiusmod tempor incididunt ut ', 31);
input.append_word('labore et dolore magna aliqua.', 31);

let compressed = DeflateEncoder::encode(input.slice(0, input.len()), Default::default());
```

### Decode

```rust
use compression::deflate::DeflateDecoder;

let decompressed = DeflateDecoder::decode(compressed.slice(0, compressed.len()), Default::default());

if decompressed.is_err() {
    return Result::Err(decompressed.unwrap_err());
}
let decompressed = decompressed.unwrap();
```

### Encode with dynamic Huffman tables

```rust
use compression::deflate::{DeflateEncoder, DeflateEncoderOptions, BlockType};
use compression::utils::slice::ByteArraySliceImpl;

let mut input: ByteArray = Default::default();
input.append_word('Lorem ipsum dolor sit amet, con', 31);
input.append_word('sectetur adipiscing elit, sed d', 31);
input.append_word('o eiusmod tempor incididunt ut ', 31);
input.append_word('labore et dolore magna aliqua.', 31);

let mut options: DeflateEncoderOptions = Default::default();
options.block_type = BlockType::DynamicHuffman;

let result = DeflateEncoder::encode(input.slice(0, input.len()), options);
```
