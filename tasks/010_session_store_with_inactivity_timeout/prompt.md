Write me an Elixir GenServer module called `SessionStore` that manages user sessions with automatic expiration after inactivity.

I need these functions in the public API:

- `SessionStore.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:timeout_ms` option for the default inactivity timeout (default 1800000, i.e. 30 minutes).

- `SessionStore.create(server, session_data)` which creates a new session containing the given data. Return `{:ok, session_id}` where session_id is a unique string. The session's inactivity timer starts from the moment of creation.

- `SessionStore.get(server, session_id)` which retrieves the session data. Return `{:ok, data}` if the session exists and has not expired, or `{:error, :not_found}` if it doesn't exist or has expired. A successful get must reset the inactivity timer.

- `SessionStore.update(server, session_id, new_data)` which replaces the session's stored data. Return `{:ok, new_data}` on success or `{:error, :not_found}` if the session doesn't exist or has expired. A successful update must reset the inactivity timer.

- `SessionStore.touch(server, session_id)` which resets the inactivity timer without modifying the data. Return `:ok` if the session exists or `{:error, :not_found}` if it doesn't exist or has expired.

- `SessionStore.destroy(server, session_id)` which immediately removes the session. Return `:ok` regardless of whether the session existed.

Each session must be tracked independently — expiring session A must have no effect on session B. The inactivity timeout is a sliding deadline: every successful `get`, `update`, or `touch` call pushes the expiration forward by the full timeout duration from the current time.

Expired sessions should be lazily cleaned up on access, but you also need a periodic sweep so the GenServer doesn't leak memory. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any sessions whose inactivity deadline has passed.

Session IDs should be generated using `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.