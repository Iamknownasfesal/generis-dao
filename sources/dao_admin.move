module generis_dao::dao_admin {
    public struct DaoOwner has store, key { id: UID }
    public struct DaoAdmin has store, key { id: UID }

    // === Public-Mutative Functions ===

    public(package) fun new(receiver: address, ctx: &mut TxContext) {
        transfer::public_transfer(DaoOwner { id: object::new(ctx) }, receiver)
    }

    public(package) fun new_dao_admin(receiver: address, ctx: &mut TxContext) {
        transfer::public_transfer(DaoAdmin { id: object::new(ctx) }, receiver)
    }

    public entry fun new_admin(
        _: &DaoOwner,
        receiver: address,
        ctx: &mut TxContext,
    ) {
        new_dao_admin(receiver, ctx)
    }

    public entry fun burn(admin: DaoAdmin) {
        let DaoAdmin { id } = admin;
        object::delete(id)
    }
}
