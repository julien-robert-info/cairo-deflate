use compression::utils::slice::Slice;

trait Encoder<T> {
    fn encode(data: Slice<T>) -> T;
}

trait Decoder<T, U> {
    fn decode(data: Slice<T>) -> Result<T, U>;
}

impl ArrayInto<
    T, U, +Copy<T>, +Copy<U>, +Drop<T>, +Drop<U>, +Into<T, U>
> of Into<@Array<T>, Array<U>> {
    fn into(self: @Array<T>) -> Array<U> {
        let mut span = self.span();
        let mut result: Array<U> = array![];

        loop {
            match span.pop_front() {
                Option::Some(val) => result.append((*val).into()),
                Option::None => { break; },
            }
        };

        result
    }
}

impl ArrayTryInto<
    T, U, +Copy<T>, +Copy<U>, +Drop<T>, +Drop<U>, +TryInto<T, U>
> of TryInto<@Array<T>, Array<U>> {
    fn try_into(self: @Array<T>) -> Option<Array<U>> {
        let mut span = self.span();
        let mut result: Array<U> = array![];

        loop {
            match span.pop_front() {
                Option::Some(val) => {
                    let val_try_into: Option<U> = (*val).try_into();
                    match val_try_into {
                        Option::Some(val_into) => result.append(val_into),
                        Option::None => { break Option::None; },
                    }
                },
                Option::None => { break Option::Some(result.clone()); },
            }
        }
    }
}

