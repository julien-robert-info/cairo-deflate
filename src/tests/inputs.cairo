fn get_test_phrase_1() -> ByteArray {
    let mut test_phrase: ByteArray = Default::default();
    test_phrase.append_word('Blah blah blah blah blah!', 25);

    test_phrase
}
fn get_test_phrase_2() -> ByteArray {
    let mut test_phrase: ByteArray = Default::default();
    test_phrase.append_word('Four score and seven years ago ', 31);
    test_phrase.append_word('our fathers brought forth, on t', 31);
    test_phrase.append_word('his continent, a new nation, co', 31);
    test_phrase.append_word('nceived in Liberty, and dedicat', 31);
    test_phrase.append_word('ed to the proposition that all ', 31);
    test_phrase.append_word('men are created equal.', 22);

    test_phrase
}
fn get_test_phrase_3() -> ByteArray {
    let mut test_phrase: ByteArray = Default::default();
    test_phrase.append_word('go go gophers', 13);

    test_phrase
}
