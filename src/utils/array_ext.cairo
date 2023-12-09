fn concat_span<T, +Copy<T>, +Drop<T>>(mut a: Span<T>, mut b: Span<T>) -> Span<T> {
    let mut result = array![];

    loop {
        match a.pop_front() {
            Option::Some(elem) => { result.append(*elem); },
            Option::None => { break; },
        }
    };
    loop {
        match b.pop_front() {
            Option::Some(elem) => { result.append(*elem); },
            Option::None => { break; },
        }
    };

    result.span()
}
