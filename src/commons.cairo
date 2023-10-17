trait Encoder<T> {
    fn encode(data: T) -> ByteArray;
}

trait Decoder<T> {
    fn decode(data: T) -> ByteArray;
}
