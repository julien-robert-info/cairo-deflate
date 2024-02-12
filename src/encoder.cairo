use compression::utils::slice::Slice;

trait Encoder<T, U> {
    fn encode(data: Slice<T>, options: U) -> T;
}

trait Decoder<T, U> {
    fn decode(data: Slice<T>) -> Result<T, U>;
}
