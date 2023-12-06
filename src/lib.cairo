mod commons;
mod offset_length_code;
mod lz77;
mod huffman;
// mod deflate;

#[cfg(test)]
mod tests {
    mod inputs;
    mod lz77_test;
    mod huffman_test;
}
