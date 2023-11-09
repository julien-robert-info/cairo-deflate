const BYTE_LEN: u256 = 0x100;

trait Encoder<T> {
    fn encode(data: T) -> T;
}

trait Decoder<T> {
    fn decode(data: T) -> T;
}

fn felt252_word_len(word: @felt252) -> usize {
    let mut word: u256 = (*word).into();
    let mut length = 0;

    loop {
        if word == 0 {
            break;
        }

        word = word / BYTE_LEN;
        length += 1;
    };

    length
}
