# Design brief: `CumulativeLeaderboard`

## Problem

We need an Elixir module called `CumulativeLeaderboard` that maintains a leaderboard using ETS (Erlang Term Storage). Unlike an all-time-high leaderboard, a player's score here is the **running sum** of all the points they have been awarded over time.

## Constraints

- Use ETS as the backing store, a `:set` table (one row per player), created `:public`.
- Because scores accumulate, `add_points/3` MUST be a lock-free atomic increment — use `:ets.update_counter/4` with a default object so concurrent awards to the same player never lose updates. Do not use a GenServer and do not do a read-modify-write in Elixir.
- All operations must be correct when called from multiple processes concurrently: if 100 processes each award 1 point to the same player, the final total must be exactly 100.
- Distinct boards must not share state, and different `player_id` types (e.g. `"1"`, `1`, `:one`) must be treated as independent players.
- Do not use any external dependencies — only the OTP standard library.

## Required public API

1. `CumulativeLeaderboard.new(board_name)` — creates a new leaderboard. `board_name` is an atom used to name the underlying ETS table. Returns `{:ok, board}` where `board` is a reference/identifier you can pass to the other functions.
2. `CumulativeLeaderboard.add_points(board, player_id, points)` — awards `points` to a player. `player_id` can be any term (string, integer, atom). `points` must be an **integer** (it may be negative to deduct points). If the player is new, their total starts from 0 and `points` is added (so a first award of 0 registers the player with a total of 0). If the player already exists, `points` is added to the existing total. Returns `{:ok, new_total}` with the player's total after applying the increment. If `points` is not an integer (e.g. a float or a string), the call must raise a `FunctionClauseError` (guard the argument with `when is_integer(points)`), and the player must not be registered.
3. `CumulativeLeaderboard.total(board, player_id)` — reads a player's current total. Returns `{:ok, total}`, or `{:error, :not_found}` if the player has never been awarded points.
4. `CumulativeLeaderboard.top(board, n)` — retrieves the top N players by total, sorted descending. Returns a list of `{player_id, total}` tuples. If fewer than N players exist, return all of them (and `[]` when the board is empty). Negative totals sort below zero and positive totals. Ties can be returned in any order.
5. `CumulativeLeaderboard.rank(board, player_id)` — gets a player's rank and total. Returns `{:ok, rank, total}` where rank is 1-based (rank 1 = highest total), using standard competition ranking (tied players share the same rank, and the next lower group is bumped by the full size of the tied group — e.g. two players tied at rank 1 make the next player rank 3). If the player does not exist, returns `{:error, :not_found}`.

## Acceptance criteria

- All five functions above are present in the public API and behave exactly as specified, including the documented return shapes and the `{:error, :not_found}` cases.
- Non-integer `points` raises `FunctionClauseError` and leaves the player unregistered.
- Concurrent awards are never lost: 100 processes each awarding 1 point to the same player yields exactly 100.
- The increment path uses `:ets.update_counter/4` with a default object — no GenServer, no read-modify-write.
- Boards are isolated from one another, and `"1"`, `1`, and `:one` are independent players.
- Only the OTP standard library is used.
- Deliverable: the complete module in a single file.
