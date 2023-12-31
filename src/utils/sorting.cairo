fn bubble_sort_dict_keys<
    T, +Copy<T>, +Drop<T>, +PartialEq<T>, +PartialOrd<T>, +Felt252DictValue<T>, +Destruct<T>
>(
    mut keys: Array<felt252>, ref dict: Felt252Dict<T>
) -> Array<felt252> {
    if keys.len() <= 1 {
        return keys;
    }
    let mut idx1 = 0;
    let mut idx2 = 1;
    let mut sorted_iteration = 0;
    let mut sorted_keys = array![];

    loop {
        if idx2 == keys.len() {
            sorted_keys.append(*keys[idx1]);
            if sorted_iteration == 0 {
                break;
            }
            keys = sorted_keys;
            sorted_keys = array![];
            idx1 = 0;
            idx2 = 1;
            sorted_iteration = 0;
        } else {
            let value1 = dict.get(*keys[idx1]);
            let value2 = dict.get(*keys[idx2]);

            if value1 <= value2 {
                sorted_keys.append(*keys[idx1]);
                idx1 = idx2;
                idx2 += 1;
            } else {
                sorted_keys.append(*keys[idx2]);
                idx2 += 1;
                sorted_iteration = 1;
            }
        };
    };
    sorted_keys
}
