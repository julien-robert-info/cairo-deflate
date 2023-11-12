trait Encoder<T> {
    fn encode(data: T) -> T;
}

trait Decoder<T> {
    fn decode(data: T) -> T;
}
