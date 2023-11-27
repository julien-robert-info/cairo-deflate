const ESCAPE_BYTE: u8 = 0xFF;

trait Encoder<T> {
    fn encode(data: T) -> T;
}

trait Decoder<T> {
    fn decode(data: T) -> T;
}
