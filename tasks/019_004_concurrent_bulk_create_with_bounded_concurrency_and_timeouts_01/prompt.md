Write me a self-contained Elixir context module `ConcurrentCatalog` that performs **concurrent bulk creation** of items into an in-memory store using a bounded concurrency pool, with per-item timeouts and index-aware result reporting that preserves the original input order.

This is a variation on a sequential bulk endpoint: here each item is validated and inserted concurrently (each item is independent, so this is always partial), but the number of items processed simultaneously is capped, and any item whose work exceeds a timeout is killed and reported as a timeout.

**Store**
- Back the module with a named `Agent` started via `ConcurrentCatalog.start_link/0` (registered under the module name).
- Provide `ConcurrentCatalog.all/0`, `ConcurrentCatalog.count/0`, `ConcurrentCatalog.get/1` (by id), and `ConcurrentCatalog.peak/0` (the high-water mark of simultaneously-running item tasks — for verifying the concurrency bound). `get/1` returns the stored item map directly, or `nil` when no item with that id exists.
- Each stored item is `%{id: integer, name: String.t(), price: integer}`.

**Input shape**
- Each attribute map: `"name"` (required, 1–100 chars), `"price"` (required integer > 0). Two optional test hooks simulate real work: `"delay"` (integer ms the insert takes) and `"fail"` (truthy → the insert fails).

**`ConcurrentCatalog.bulk_create(list_of_attrs, opts \\ [])`**
- `opts[:max_concurrency]` (default `4`) — at most this many item tasks run at once.
- `opts[:timeout_ms]` (default `1000`) — per-item time budget; an item exceeding it is killed.
- Process items concurrently (use `Task.async_stream/3` with `ordered: true`, `on_timeout: :kill_task`, and the given `max_concurrency`/`timeout`) so that CPU/IO-bound insert work parallelizes, yet the returned results are in **original input order**, exactly one per item.
- Each result carries the zero-based index: `{index, :ok, item}`, or `{index, :error, reason}` where `reason` is `{:validation, errors_map}`, `:insert_failed`, or `:timeout`. The `errors_map` maps the offending field's **string** key exactly as in the input attrs to a list of error message strings — e.g. `%{"price" => ["must be a positive integer"]}`.
- Return the plain list of results (no `{:ok, _}`/`{:error, _}` wrapper — every item is independent).

The store must remain consistent under concurrent access (Agent serializes writes), the running-task high-water mark must never exceed `max_concurrency`, and timed-out or failed items must not be inserted. Use only Elixir/OTP standard library — no external dependencies.