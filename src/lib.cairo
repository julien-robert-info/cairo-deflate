mod utils {
    mod bit_array_ext;
    mod byte_array_ext;
    mod dict_ext;
    mod sorting;
}
mod commons;
mod sequence;
mod lz77;
mod huffman;
mod huffman_table;

#[cfg(test)]
mod tests {
    mod inputs;
    mod lz77_test;
    mod huffman_test;
    mod utils {
        mod sorting_test;
        mod byte_array_ext_test;
    }
}
