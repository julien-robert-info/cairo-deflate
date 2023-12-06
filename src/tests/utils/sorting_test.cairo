use compression::utils::sorting;

#[test]
#[available_gas(1200000)]
fn test_sorting() {
    let mut dict: Felt252Dict<usize> = Default::default();
    dict.insert('a', 5);
    dict.insert('b', 3);
    dict.insert('c', 12);
    dict.insert('d', 8);
    dict.insert('e', 2);
    dict.insert('f', 7);
    let keys: Array<felt252> = array!['a', 'b', 'c', 'd', 'e', 'f'];

    let result: Array<felt252> = sorting::bubble_sort_dict_keys_desc(keys, ref dict);
    let expected: Array<felt252> = array!['c', 'd', 'f', 'a', 'b', 'e'];

    assert(result == expected, 'unexpected result')
}
