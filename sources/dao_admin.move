module generis_dao::dao_admin {
    public struct DaoAdmin has key, store { id: UID }

    public(package) fun new(ctx: &mut TxContext): DaoAdmin {
        DaoAdmin {id: object::new(ctx)}
    }

    public fun new_from_another_admin(_: &DaoAdmin, ctx: &mut TxContext): DaoAdmin {
        new(ctx)
    }

    public fun burn(admin: DaoAdmin) {
        let DaoAdmin { id } = admin;
        object::delete(id)
    }
}
