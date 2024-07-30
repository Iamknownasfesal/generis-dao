module generis_dao::dao_admin {
    public struct DaoOwner has store, key { id: UID }
    public struct DaoAdmin has store, key { id: UID }

    // === Public-Mutative Functions ===

    public(package) fun new(ctx: &mut TxContext, receiver: address) {
        transfer::public_transfer(DaoOwner { id: object::new(ctx) }, receiver)
    }

    public(package) fun new_dao_admin(ctx: &mut TxContext, receiver: address) {
        transfer::public_transfer(DaoAdmin { id: object::new(ctx) }, receiver)
    }

    public fun new_admin(_: &DaoOwner, ctx: &mut TxContext, receiver: address) {
        new_dao_admin(ctx, receiver)
    }

    public fun burn(admin: DaoAdmin) {
        let DaoAdmin { id } = admin;
        object::delete(id)
    }
}
