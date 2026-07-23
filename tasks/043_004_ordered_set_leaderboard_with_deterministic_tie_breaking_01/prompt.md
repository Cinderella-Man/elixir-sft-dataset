# Design brief: `OrderedLeaderboard`

## Problem

We need an all-time-high leaderboard for Elixir, backed by ETS (Erlang Term Storage), that behaves
**deterministically** under ties and hands out **unique ordinal ranks**. Two players holding the same
score must not be ordered arbitrarily: whoever reached that score *first* ranks higher. And no two
players may share a position — every player gets a distinct 1-based position (no shared ranks).

## Constraints

- The main store is an ETS `:ordered_set`, created `:public`, whose key is a composite tuple of the
  form `{negated_score, sequence, player_id}`. Encoding score-descending then arrival order into the
  key means ETS's native key ordering already yields score-descending then arrival-ascending — no
  sorting pass required.
- A secondary `:set` index maps `player_id` to its current composite key, so a player's old entry can
  be found and deleted on update.
- Writes are serialized through a small GenServer that owns both tables, so the composite key and a
  global sequence counter stay consistent. That GenServer serializes `submit_score/3` and assigns a
  monotonically increasing sequence number, making tie-breaking consistent.
- Reads go straight to the public ETS tables for lock-free concurrency: `top/2` and `rank/2` must NOT
  call the GenServer.
- No external dependencies — only the OTP standard library.
- Deliverable: the complete module in a single file, named `OrderedLeaderboard`.

## Required interface

1. `OrderedLeaderboard.new(board_name)` — creates a leaderboard. `board_name` is an atom used to name
   the underlying ETS table. Returns `{:ok, board}` where `board` is an identifier (it may be a map or
   struct holding the server and table handles) that you pass to the other functions.
2. `OrderedLeaderboard.submit_score(board, player_id, score)` — submits a score. `player_id` can be any
   term; `score` is a number. Only the player's all-time highest score is kept: a strictly higher score
   overwrites the previous one (and, for tie-breaking purposes, counts as being "reached" at submission
   time); a lower-or-equal score is a no-op. Always returns `:ok`.
3. `OrderedLeaderboard.top(board, n)` — returns the top N players as `{player_id, score}` tuples in
   final leaderboard order (score descending; ties broken by earliest arrival at that score). If fewer
   than N players exist, returns all of them. Reads must traverse the ordered set in key order.
4. `OrderedLeaderboard.rank(board, player_id)` — returns `{:ok, rank, score}` where `rank` is the
   player's unique 1-based ordinal position in that same total order, or `{:error, :not_found}` if the
   player does not exist.

## Acceptance criteria

- Ordering is deterministic: equal scores resolve by earliest arrival at that score, ranking the
  earlier arriver higher.
- `rank/2` returns unique ordinal positions — tied scores get distinct, deterministic ranks. This is a
  deliberate contrast to competition ranking.
- A submission at or below a player's stored high score leaves the board unchanged; a strictly higher
  one replaces the old entry and re-times the player's arrival.
- `top/2` and `rank/2` are answered entirely from the public ETS tables, with no GenServer call on the
  read path.
- The implementation uses an ETS `:ordered_set` for the main store plus a `:set` player index, both
  owned by the GenServer, and compiles and runs with only the OTP standard library.
