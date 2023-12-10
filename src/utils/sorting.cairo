fn bubble_sort_dict_keys<
    T, +Copy<T>, +Drop<T>, +PartialEq<T>, +PartialOrd<T>, +Felt252DictValue<T>, +Destruct<T>
>(
    mut keys: Span<felt252>, ref dict: Felt252Dict<T>
) -> Span<felt252> {
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
            keys = sorted_keys.span();
            sorted_keys = array![];
            idx1 = 0;
            idx2 = 1;
            sorted_iteration = 0;
        } else {
            let key1: u256 = (*keys[idx1]).into();
            let key2: u256 = (*keys[idx2]).into();
            let value1 = dict.get(*keys[idx1]);
            let value2 = dict.get(*keys[idx2]);

            if value1 < value2 || (value1 == value2 && key1 > key2) {
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
    sorted_keys.span()
}
fn bubble_sort_elements(mut array: Span<felt252>) -> Span<felt252> {
    if array.len() <= 1 {
        return array;
    }
    let mut idx1 = 0;
    let mut idx2 = 1;
    let mut sorted_iteration = 0;
    let mut sorted_array = array![];

    loop {
        if idx2 == array.len() {
            sorted_array.append(*array[idx1]);
            if sorted_iteration == 0 {
                break;
            }
            array = sorted_array.span();
            sorted_array = array![];
            idx1 = 0;
            idx2 = 1;
            sorted_iteration = 0;
        } else {
            let val1: u256 = (*array[idx1]).into();
            let val2: u256 = (*array[idx2]).into();
            if val1 < val2 {
                sorted_array.append(*array[idx1]);
                idx1 = idx2;
                idx2 += 1;
            } else {
                sorted_array.append(*array[idx2]);
                idx2 += 1;
                sorted_iteration = 1;
            }
        };
    };
    sorted_array.span()
}
