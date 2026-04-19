Write me an Elixir GenServer module called `BatchCollector` that collects individual items submitted under a key and flushes them as a batch to a user-supplied function, so that multiple rapid writes are coalesced into a single batch operation.

I need these functions in the public API:

- `BatchCollector.start_link(opts)` to start the process. It should accept a `:name` option for process registration and a required `:flush_interval_ms` option (the maximum time to wait before flushing a batch, even if the count threshold hasn't been reached).

- `BatchCollector.submit(server, key, item, flush_fn, opts \\ [])` which adds `item` to the batch buffer for `key`. The caller blocks until its batch is flushed. `flush_fn` is a single-arity function that receives the list of all collected items for that key (in submission order) and returns `{:ok, result}` or `{:error, reason}`. The optional `:max_batch_size` in opts (default 10) controls the count threshold — when the buffer for a key reaches this size, it flushes immediately without waiting for the timer.

  Returns whatever `flush_fn` returns. All callers whose items are in the same batch receive the same result.

- `BatchCollector.pending_count(server, key)` which returns the number of items currently buffered for the given key (0 if no pending batch).

The lifecycle of a batch for a given key works like this:
1. The first `submit` for a key starts a timer of `flush_interval_ms` and puts the item in the buffer.
2. Subsequent `submit` calls for the same key add their items to the buffer and register as waiters.
3. When either the timer fires OR `max_batch_size` is reached (whichever comes first), the batch is flushed: `flush_fn` is called with the full list of items in a spawned Task (so the GenServer remains responsive), and all waiting callers receive the result.
4. After the flush, the key is cleared for new batches.

If `flush_fn` raises an exception, all callers in that batch should receive `{:error, {:exception, exception}}`.

If a timer fires but the batch was already flushed (because the count threshold was hit first), the timer message should be harmlessly ignored.

Different keys are completely independent — they have separate buffers, timers, and thresholds.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.