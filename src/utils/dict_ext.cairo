fn clone_from_keys<T, +Copy<T>, +Drop<T>, +Felt252DictValue<T>>(
    keys: @Array<felt252>, ref dict: Felt252Dict<T>
) -> Felt252Dict<T> {
    let mut result: Felt252Dict<T> = Default::default();
    let mut keys = keys.span();

    loop {
        match keys.pop_front() {
            Option::Some(key) => {
                let key = *key;
                let value = dict.get(key);
                result.insert(key, value);
            },
            Option::None => { break; },
        }
    };

    result
}
