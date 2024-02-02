use compression::tests::inputs;
use compression::utils::byte_array_ext::SubStrImpl;

#[test]
#[available_gas(600000)]
fn test_sub_string() {
    let mut string = inputs::get_test_phrase_3();
    let sub_str = string.sub_str(6, 7);

    let mut expected_sub_str: ByteArray = Default::default();
    expected_sub_str.append_word('gophers', 7);

    assert(sub_str == expected_sub_str, 'unexpected before')
}
