Write me an Elixir GenServer module called `LFUCache` that implements a **Least Frequently Used** cache backed by ETS.

Unlike an LRU cache (which evicts the entry that was accessed least recently), this cache evicts the entry that has been accessed the *fewest times*. When two entries are tied on access frequency, break the tie by evicting the one that is least recently used among them.

I need these functions in the public API:
- `LFUCache.start_link(opts)` to start the process. It should accept a `:name` option (required) used both to register the process and to name the ETS tables, and a `:max_size` option (required) that caps how many entries the cache may hold at once.
- `LFUCache.get(name, key)` which looks up a key. Return `{:ok, value}` if the key exists, or `:miss` if it does not. A successful get counts as one access and must increment that entry's frequency.
- `LFUCache.put(name, key, value)` which inserts or updates an entry. A brand-new entry starts with a frequency of 1. If the key already exists, update its value and count the write as an access (increment its frequency). If the cache is already at `max_size` and the key is new, evict the least frequently used entry (tie broken by least recently used) before inserting. Always return `:ok`.

Implementation requirements:
- Use two ETS tables owned by the GenServer: one that maps `key → {value, frequency, seq}` for O(1) lookups, and one ordered set whose key is the composite `{frequency, seq}` (mapping to the cache key) so the least-frequently-used entry — with a least-recently-used tie-break — is always at the front for O(log n) eviction.
- Use a single monotonically increasing counter (`seq`) kept in the GenServer state as the recency stamp, so ordering is deterministic and fully testable without any clock mocking. Every access (get, put-insert, put-update) draws a fresh `seq`.
- All mutations (`put`, eviction, and the frequency bump on `get`) must go through the GenServer process to serialise writes; reads may read directly from ETS first.
- There is no TTL or background cleanup; entries only leave the cache through frequency-based eviction.

Give me the complete module in a single file. Use only the OTP standard library — no external dependencies.