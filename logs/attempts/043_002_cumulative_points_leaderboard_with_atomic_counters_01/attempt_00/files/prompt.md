Write me an Elixir module called `CumulativeLeaderboard` that maintains a leaderboard using ETS (Erlang Term Storage), where — unlike an all-time-high leaderboard — a player's score is the **running sum** of all the points they have been awarded over time.

I need these functions in the public API:
- `CumulativeLeaderboard.new(board_name)` to create a new leaderboard. `board_name` is an atom
  used to name the underlying ETS table. Return `{:ok, board}` where `board` is a
  reference/identifier you can pass to the other functions.
- `CumulativeLeaderboard.add_points(board, player_id, points)` to award `points` to a player.
  `player_id` can be any term (string, integer, atom). `points` must be an **integer** (it may be
  negative to deduct points). If the player is new, their total starts from 0 and `points` is added.
  If the player already exists, `points` is added to the existing total. Return `{:ok, new_total}`
  with the player's total after applying the increment.
- `CumulativeLeaderboard.total(board, player_id)` to read a player's current total. Return
  `{:ok, total}` or `{:error, :not_found}` if the player has never been awarded points.
- `CumulativeLeaderboard.top(board, n)` to retrieve the top N players by total, sorted descending.
  Return a list of `{player_id, total}` tuples. If fewer than N players exist, return all of them.
  Ties can be returned in any order.
- `CumulativeLeaderboard.rank(board, player_id)` to get a player's rank and total. Return
  `{:ok, rank, total}` where rank is 1-based (rank 1 = highest total), using standard competition
  ranking (tied players share the same rank). If the player does not exist, return `{:error, :not_found}`.

Implementation requirements:
- Use ETS as the backing store, a `:set` table (one row per player), created `:public`.
- Because scores accumulate, `add_points/3` MUST be a lock-free atomic increment — use
  `:ets.update_counter/4` with a default object so concurrent awards to the same player never lose
  updates. Do not use a GenServer and do not do a read-modify-write in Elixir.
- All operations must be correct when called from multiple processes concurrently: if 100 processes
  each award 1 point to the same player, the final total must be exactly 100.
- Do not use any external dependencies — only the OTP standard library.

Give me the complete module in a single file.