module generis_dao::display_wrapper;

use sui::display::Display;

public struct DisplayWrapper<phantom T: key> has key, store {
    id: UID,
    display: Display<T>,
}

public fun new<T: key>(
    display: Display<T>,
    ctx: &mut TxContext,
): DisplayWrapper<T> {
    DisplayWrapper {
        id: object::new(ctx),
        display,
    }
}
