Write me an Elixir module called `Leaderboard` that maintains a leaderboard using ETS (Erlang Term Storage).

I need these functions in the public API:
- `Leaderboard.new(board_name)` to create a new leaderboard. `board_name` is an atom used
  to name the underlying ETS table. It should return `{:ok, board}` where `board` is a
  reference/identifier you can pass to the other functions.
- `Leaderboard.submit_score(board, player_id, score)` to submit a score for a player.
  `player_id` can be any term (string, integer, atom). `score` is a number. Only the
  player's all-time highest score should be kept — submitting a lower score must be a
  no-op, submitting a higher score must overwrite the previous one. Always return `:ok`.
- `Leaderboard.top(board, n)` to retrieve the top N players by score, sorted descending.
  Return a list of `{player_id, score}` tuples. If fewer than N players exist, return all
  of them. Ties in score can be returned in any order.
- `Leaderboard.rank(board, player_id)` to get a specific player's rank and score. Return
  `{:ok, rank, score}` where rank is 1-based (rank 1 = highest score). If the player does
  not exist, return `{:error, :not_found}`. Ties should give the same rank to all tied
  players (dense ranking is not required — any consistent tie-breaking is fine as long as
  the contract is documented).

Implementation requirements:
- Use ETS as the backing store. The table should be of type `:set` (one row per player).
- `new/1` should create a public ETS table so callers don't have to worry about process
  ownership for the purposes of this exercise.
- All operations must work correctly when called from multiple processes concurrently.
  Since ETS provides concurrency for free on `:public` tables, you do not need a GenServer
  unless you want one.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.