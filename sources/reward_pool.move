module generis_dao::reward_pool {
    use sui::{balance::Balance, coin::{Self, Coin}};

    // === Structs ===

    /// A reward pool is a store of a specific token that is used to reward users for their contributions to the DAO.
    public struct RewardPool<phantom T> has store, key {
        id: UID,
        /// The balance of the reward pool.
        balance: Balance<T>,
    }

    // === Public-Mutative Functions ===

    public fun new<T>(in: Coin<T>, ctx: &mut TxContext): RewardPool<T> {
        RewardPool { id: object::new(ctx), balance: in.into_balance() }
    }

    public fun destroy<T>(pool: RewardPool<T>, ctx: &mut TxContext): Coin<T> {
        let RewardPool { id, balance } = pool;

        object::delete(id);

        coin::from_balance(balance, ctx)
    }

    // === Public-View Functions ===

    public fun value<T>(pool: &RewardPool<T>): u64 {
        pool.balance.value()
    }
}
