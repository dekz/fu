use std::{
    env, process,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread,
    time::Instant,
};

use alloy::primitives::{address, b256, hex, keccak256, Address, B256};

const DEPLOYER: Address = address!("4e59b44847b379578588920cA78FbF26c0B4956C");
const UNISWAP_FACTORY: Address = address!("5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f");
const WETH: Address = address!("C02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
const UNISWAP_PAIR_INITCODE_HASH: B256 =
    b256!("96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f");
const N_THREADS: usize = 8;
const BATCH_SIZE: usize = 4096;

fn leading_zeros(addr: Address) -> Option<u32> {
    let b = addr.as_slice();
    let mut r = 0u32;

    for c in b.chunks_exact(4) {
        let w = u32::from_be_bytes(c.try_into().ok()?);
        let z = w.leading_zeros();
        if z < 32 {
            return Some(r + z);
        }
        r += 32;
    }
    Some(r)
}

#[repr(C)]
struct B256Aligned(B256, [usize; 0]);

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("Usage: {} <initcode_hash> <leading_zeros>", args[0]);
        eprintln!("Example:");
        eprintln!(
            "  {} 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54 16",
            args[0]
        );
        process::exit(1);
    }

    let initcode: B256 = hex::FromHex::from_hex(args[1].clone())?;

    let target: usize = args[2]
        .parse()
        .expect("invalid integer for number of leading zero bits");

    println!("Required leading zero bits: {target}");

    let mut handles = Vec::with_capacity(N_THREADS);
    let found = Arc::new(AtomicBool::new(false));
    let timer = Instant::now();

    for thread_idx in 0..N_THREADS {
        let found = Arc::clone(&found);

        let handle = thread::spawn(move || {
            let mut salt = B256Aligned(B256::ZERO, []);
            // SAFETY: B256 is aligned enough to treat the last 8 bytes as a `u64`.
            let salt_word = unsafe {
                &mut *salt
                    .0
                    .as_mut_ptr()
                    .add(32 - std::mem::size_of::<u64>())
                    .cast::<u64>()
            };
            *salt_word = (thread_idx as u64).to_be();
            let mut pair_salt_input = [0u8; 40];

            'outer: loop {
                if found.load(Ordering::Relaxed) {
                    break None;
                }

                for _ in 0..BATCH_SIZE {
                    let token_address = DEPLOYER.create2(&salt.0, &initcode);

                    let (token0, token1) = if token_address < WETH {
                        (token_address, WETH)
                    } else {
                        (WETH, token_address)
                    };

                    pair_salt_input[0..20].copy_from_slice(token0.as_slice());
                    pair_salt_input[20..40].copy_from_slice(token1.as_slice());
                    let pair_salt = keccak256(&pair_salt_input);

                    let pair_address =
                        UNISWAP_FACTORY.create2(&pair_salt, &UNISWAP_PAIR_INITCODE_HASH);

                    if leading_zeros(pair_address)? as usize == target {
                        found.store(true, Ordering::Relaxed);
                        break 'outer Some((salt.0, token_address, pair_address));
                    }

                    *salt_word = u64::from_be(*salt_word)
                        .wrapping_add(N_THREADS as u64)
                        .to_be();
                }
            }
        });

        handles.push(handle);
    }

    let results = handles
        .into_iter()
        .filter_map(|h| h.join().unwrap())
        .collect::<Vec<_>>();
    let (salt, token_address, pair_address) = results.into_iter().min().unwrap();

    println!(
        "Successfully found contract address in {:?}",
        timer.elapsed()
    );
    println!("Salt:          {salt}");
    println!("Token Address: {token_address}");
    println!("Pair Address:  {pair_address}");

    Ok(())
}
