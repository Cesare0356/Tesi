#[derive(Drop, Serde)]
struct MyData {
    useraddress: starknet::EthAddress,
    value: felt252,
}


#[starknet::interface]
trait IRestaurantReview<T> {
    fn leave_review(
        ref self: T,
        user_address: starknet::EthAddress, 
        to_address: starknet::EthAddress,
        rating: felt252,
        text: Array<felt252>
    );
}

#[starknet::contract]
mod contract_msg {
    use starknet::storage::StorageMapReadAccess;
    use starknet::storage::StorageMapWriteAccess;
    use starknet::event::EventEmitter;
    use super::{IRestaurantReview, MyData};
    use starknet::{EthAddress, SyscallResultTrait};
    use core::num::traits::Zero;
    use starknet::syscalls::send_message_to_l1_syscall;
    use starknet::storage::Map;

    #[storage]
    struct Storage {
        authorized: Map<felt252, bool>,
        has_reviewed: Map<felt252, bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ValueReceivedFromL1: ValueReceived,
        ReviewSubmitted: ReviewData,
    }

    #[derive(Drop, starknet::Event)]
    struct ValueReceived {
        #[key]
        l1_address: felt252,
        value: felt252
    }
    
    #[derive(Drop, starknet::Event)]
    struct ReviewData {
        #[key]
        l1_address: felt252,
        rating: felt252,
        review: Array<felt252>,
    }
    #[derive(Drop, Serde)]
    struct Result {
        user_addr: starknet::EthAddress,
        result: felt252,
    }

    #[l1_handler]
    fn msg_handler_value(ref self: ContractState, from_address: felt252, data: MyData) {
        assert(!data.value.is_zero(), 'Dato non valido');
        let l1_address: felt252 = data.useraddress.into();
        self.authorized.write(l1_address, true);
        self.has_reviewed.write(l1_address, false);
        self.emit(ValueReceived {
            l1_address,
            value: data.value,
        });
    }

    #[abi(embed_v0)]
    impl ReviewImpl of IRestaurantReview<ContractState> {
        fn leave_review(ref self: ContractState, user_address: EthAddress, to_address: EthAddress, rating: felt252, text: Array<felt252>) { 
            let res: Result = Result {
                user_addr: user_address,
                result: 1,
            };
            
            let caller:felt252 = to_address.into();
            if (self.has_reviewed.read(caller)) {
                let res: Result = Result {
                    user_addr: user_address,
                    result: 0,
                };
                let mut buf: Array<felt252> = array![];
                res.serialize(ref buf);
                send_message_to_l1_syscall(to_address.into(), buf.span()).unwrap_syscall();
                return;
            }
            
            let rating_u8: u8 = rating.try_into().unwrap();

            assert(rating_u8 >= 1, 'Rating troppo basso');
            assert(rating_u8 <= 5, 'Rating troppo alto');

            let review_len = text.len();
            assert(review_len > 3, 'Review troppo corta');
            assert(review_len < 100, 'Review troppo lunga');
        
            let mut i = 0;
            while i != review_len {
                let c: felt252 = text.at(i).clone();

                let c_u8: u8 = c.try_into().unwrap();

                assert(c_u8 >= 32, 'Carattere non valido');
                assert(c_u8 <= 126, 'Carattere non valido');
                i += 1;
            };
            
            self.has_reviewed.write(caller, true);
            
            self.emit(ReviewData {
                l1_address: caller,
                rating: rating,
                review: text.clone(),
            });
            let mut buf: Array<felt252> = array![];
            res.serialize(ref buf);
            send_message_to_l1_syscall(to_address.into(), buf.span()).unwrap_syscall();
        }
    }     
}  
