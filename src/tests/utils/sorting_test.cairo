use compression::utils::sorting;

#[test]
#[available_gas(1500000)]
fn test_sorting() {
    let mut dict: Felt252Dict<usize> = Default::default();
    dict.insert('a', 5);
    dict.insert('b', 2);
    dict.insert('c', 12);
    dict.insert('d', 8);
    dict.insert('e', 2);
    dict.insert('f', 7);
    let keys = array!['a', 'b', 'c', 'd', 'e', 'f'].span();

    let result = sorting::bubble_sort_dict_keys(keys, ref dict);
    let expected = array!['e', 'b', 'a', 'f', 'd', 'c'].span();

    assert(result == expected, 'unexpected result')
}
