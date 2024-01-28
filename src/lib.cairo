mod utils {
    mod dict_ext;
    mod sorting;
}
mod commons;
mod sequence;
mod lz77;
mod huffman;
// mod deflate;

#[cfg(test)]
mod tests {
    mod inputs;
    mod lz77_test;
    mod huffman_test;
    mod utils {
        mod sorting_test;
    }
}
