Write me an Elixir module called `OrderedLeaderboard` that maintains an all-time-high leaderboard using ETS (Erlang Term Storage), but with **deterministic tie-breaking** and **unique ordinal ranks**: when two players share the same score, whoever reached that score *first* ranks higher, and every player gets a distinct 1-based position (no shared ranks).

To make this efficient and deterministic, use an ETS `:ordered_set` whose key is a composite tuple that encodes score-descending, then arrival order. Serialize writes through a small GenServer that owns the tables (so the composite key and a global sequence counter stay consistent), while reads go straight to the public ETS tables for lock-free concurrency.

I need these functions in the public API:
- `OrderedLeaderboard.new(board_name)` to create a leaderboard. `board_name` is an atom used to name
  the underlying ETS table. Return `{:ok, board}` where `board` is an identifier (it may be a map or
  struct holding the server and table handles) that you pass to the other functions.
- `OrderedLeaderboard.submit_score(board, player_id, score)` to submit a score. `player_id` can be any
  term; `score` is a number. Only the player's all-time highest score is kept: a strictly higher score
  overwrites the previous one (and, for tie-breaking purposes, counts as being "reached" at submission
  time); a lower-or-equal score is a no-op. Always return `:ok`.
- `OrderedLeaderboard.top(board, n)` to return the top N players, as `{player_id, score}` tuples in
  final leaderboard order (score descending; ties broken by earliest arrival at that score). If fewer
  than N players exist, return all of them. Reads must traverse the ordered set in key order.
- `OrderedLeaderboard.rank(board, player_id)` to return `{:ok, rank, score}` where `rank` is the
  player's unique 1-based ordinal position in that same total order, or `{:error, :not_found}` if the
  player does not exist.

Implementation requirements:
- The main store is an ETS `:ordered_set`, created `:public`, with a composite key of the form
  `{negated_score, sequence, player_id}` so ETS's native key ordering yields score-descending then
  arrival-ascending. Maintain a secondary `:set` index from `player_id` to its current composite key
  so you can find and delete a player's old entry on update.
- A GenServer owns both tables and serializes `submit_score/3`, assigning a monotonically increasing
  sequence number so tie-breaking is consistent. `top/2` and `rank/2` must NOT call the GenServer —
  they read the public ETS tables directly.
- `rank/2` returns unique ordinal positions (tied scores get distinct, deterministic ranks), which is
  a deliberate contrast to competition ranking.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.