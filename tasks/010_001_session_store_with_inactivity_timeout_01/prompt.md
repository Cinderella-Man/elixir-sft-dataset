# SessionStore — Specification

## Overview

`SessionStore` is an Elixir GenServer module that manages user sessions with automatic expiration after inactivity. It must be delivered as a complete module in a single file, using only the OTP standard library with no external dependencies.

Each session is tracked independently: expiring session A must have no effect on session B. The inactivity timeout is a sliding deadline — every successful `get`, `update`, or `touch` call pushes the expiration forward by the full timeout duration measured from the current time. The session's inactivity timer begins at the moment of creation.

Session IDs must be generated using `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)`.

## API

The public API comprises the following functions:

- `SessionStore.start_link(opts)` starts the process. It accepts a `:clock` option, which is a zero-arity function returning the current time in milliseconds; when not provided, it defaults to `fn -> System.monotonic_time(:millisecond) end`. It also accepts a `:name` option for process registration and a `:timeout_ms` option for the default inactivity timeout (default 1800000, i.e. 30 minutes).

- `SessionStore.create(server, session_data)` creates a new session containing the given data. It returns `{:ok, session_id}`, where session_id is a unique string. The session's inactivity timer starts from the moment of creation.

- `SessionStore.get(server, session_id)` retrieves the session data. It returns `{:ok, data}` if the session exists and has not expired, or `{:error, :not_found}` if it does not exist or has expired. A successful get must reset the inactivity timer.

- `SessionStore.update(server, session_id, new_data)` replaces the session's stored data. It returns `{:ok, new_data}` on success, or `{:error, :not_found}` if the session does not exist or has expired. A successful update must reset the inactivity timer.

- `SessionStore.touch(server, session_id)` resets the inactivity timer without modifying the data. It returns `:ok` if the session exists, or `{:error, :not_found}` if it does not exist or has expired.

- `SessionStore.destroy(server, session_id)` immediately removes the session. It returns `:ok` regardless of whether the session existed.

## Cleanup and lifecycle

Expired sessions are to be lazily cleaned up on access. In addition, a periodic sweep is required so that the GenServer does not leak memory. The periodic cleanup runs using `Process.send_after` every 60 seconds (configurable via the `:cleanup_interval_ms` option) and removes any sessions whose inactivity deadline has passed.

## Edge cases

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.
