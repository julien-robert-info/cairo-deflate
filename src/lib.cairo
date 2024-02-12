mod utils {
    mod array_ext;
    mod bit_array_ext;
    mod slice;
    mod dict_ext;
    mod sorting;
}
mod encoder;
mod sequence;
mod lz77;
mod huffman;
mod huffman_table;
mod deflate;

#[cfg(test)]
mod tests {
    mod inputs;
    mod lz77_test;
    mod huffman_test;
    mod deflate_test;
    mod utils {
        mod sorting_test;
    }
}
