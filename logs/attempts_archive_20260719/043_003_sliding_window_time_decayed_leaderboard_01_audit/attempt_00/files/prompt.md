Write me an Elixir module called `SlidingWindowLeaderboard` that maintains a **time-decayed** leaderboard using ETS (Erlang Term Storage). Instead of an all-time score, a player's leaderboard score is the sum of the points from scoring events that occurred within a rolling time window (e.g. the last 60 seconds). Old events "fall off" the window and stop counting.

Time is always passed in explicitly as a millisecond integer `now` so the module is fully deterministic and testable — never read the system clock.

I need these functions in the public API:
- `SlidingWindowLeaderboard.new(board_name, window_ms)` to create a leaderboard. `board_name` is an
  atom naming the underlying ETS table, `window_ms` is a positive integer window size in
  milliseconds. Return `{:ok, board}` where `board` is an identifier you pass to the other functions.
- `SlidingWindowLeaderboard.record(board, player_id, points, now)` to record a scoring event of
  `points` (a number) for `player_id` at timestamp `now`. Return `:ok`.
- `SlidingWindowLeaderboard.score(board, player_id, now)` to compute a player's **active** score as
  of `now`: the sum of points from that player's events whose timestamp is strictly greater than
  `now - window_ms`. Return `{:ok, active_score}`. If the player has no active events (they never
  recorded anything, or all their events have expired), return `{:error, :not_found}`.
- `SlidingWindowLeaderboard.top(board, n, now)` to return the top N players by active score at `now`,
  sorted descending, as `{player_id, active_score}` tuples. Players with no active events must not
  appear. If fewer than N active players exist, return all of them.
- `SlidingWindowLeaderboard.rank(board, player_id, now)` to return `{:ok, rank, active_score}` for a
  player at `now` (1-based, standard competition ranking, tied active scores share a rank), or
  `{:error, :not_found}` if the player has no active events.
- `SlidingWindowLeaderboard.prune(board, now)` to garbage-collect: permanently delete every event
  whose timestamp is `<= now - window_ms`. Return the number of events deleted.

Implementation requirements:
- Use ETS as the backing store. Because a player accumulates many events over time, use a
  `:duplicate_bag` table keyed by `player_id`, storing one row per event, created `:public`.
- Recording an event must be a single atomic `:ets.insert/2` so multiple processes can record
  concurrently without coordination or lost writes. Do not use a GenServer.
- An event exactly at the cutoff (`timestamp == now - window_ms`) is considered expired.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.