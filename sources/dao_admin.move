module generis_dao::dao_admin {
    public struct DaoOwner has store, key { id: UID }
    public struct DaoAdmin has store, key { id: UID }

    // === Public-Mutative Functions ===

    public(package) fun new(receiver: address, ctx: &mut TxContext) {
        transfer::public_transfer(DaoOwner { id: object::new(ctx) }, receiver)
    }

    public fun new_dao_admin(ctx: &mut TxContext): DaoAdmin {
        DaoAdmin { id: object::new(ctx) }
    }

    public fun new_admin(_: &DaoOwner, ctx: &mut TxContext): DaoAdmin {
        new_dao_admin(ctx)
    }

    public entry fun burn(admin: DaoAdmin) {
        let DaoAdmin { id } = admin;
        object::delete(id)
    }
}
