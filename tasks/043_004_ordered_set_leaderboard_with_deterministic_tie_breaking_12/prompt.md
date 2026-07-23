# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `top` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `top` missing

```elixir
defmodule OrderedLeaderboard do
  @moduledoc """
  An all-time-high leaderboard backed by an ETS `:ordered_set`, giving
  deterministic tie-breaking and unique ordinal ranks.

  ## Design

  The main table is an `:ordered_set` whose key is a composite tuple
  `{-score, sequence, player_id}`.  Because ETS orders `:ordered_set` keys by
  Erlang term order, this yields **score descending** (via the negated score)
  and then **arrival ascending** (via a monotonically increasing sequence
  number).  So among players with an equal score, whoever reached that score
  first sorts earlier, and every player occupies a distinct position.

  A secondary `:set` index maps `player_id` to its current composite key so a
  player's old row can be found and deleted when their score improves.

  A GenServer owns both tables and serializes `submit_score/3`, handing out the
  sequence numbers so the composite key stays globally consistent.  Reads
  (`top/2`, `rank/2`) go straight to the public ETS tables and never touch the
  GenServer, so they are lock-free and concurrent.

  ## Rank contract

  `rank/2` returns a UNIQUE 1-based ordinal position: tied scores receive
  distinct, deterministic ranks (earliest arrival wins), in contrast to
  competition ranking where ties share a rank.
  """

  use GenServer

  @type board :: %{server: pid(), entries: :ets.tid(), index: :ets.tid()}
  @type player_id :: term()

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new leaderboard.  Returns `{:ok, board}` where `board` carries the
  owning server and the two table handles.
  """
  @spec new(atom()) :: {:ok, board()}
  def new(board_name) when is_atom(board_name) do
    {:ok, pid} = GenServer.start_link(__MODULE__, board_name)
    GenServer.call(pid, :board)
  end

  @doc """
  Submits `score` for `player_id`, keeping only the all-time high.  Serialized
  through the owning GenServer.  Always returns `:ok`.
  """
  @spec submit_score(board(), player_id(), number()) :: :ok
  def submit_score(board, player_id, score) when is_number(score) do
    GenServer.call(board.server, {:submit, player_id, score})
  end

  def top(_board, 0) do
    # TODO
  end

  @doc """
  Returns `{:ok, rank, score}` (unique 1-based ordinal position) or
  `{:error, :not_found}`.  Reads the ETS tables directly.
  """
  @spec rank(board(), player_id()) :: {:ok, pos_integer(), number()} | {:error, :not_found}
  def rank(board, player_id) do
    case :ets.lookup(board.index, player_id) do
      [] ->
        {:error, :not_found}

      [{^player_id, {neg_score, _seq, _pid} = key}] ->
        match_spec = [{{:"$1", :_, :_}, [{:<, :"$1", {:const, key}}], [true]}]
        before = :ets.select_count(board.entries, match_spec)
        {:ok, before + 1, -neg_score}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(board_name) do
    entries =
      :ets.new(board_name, [:ordered_set, :public, :named_table, read_concurrency: true])

    index =
      :ets.new(:"#{board_name}_index", [:set, :public, read_concurrency: true])

    {:ok, %{entries: entries, index: index, seq: 0}}
  end

  @impl true
  def handle_call(:board, _from, state) do
    board = %{server: self(), entries: state.entries, index: state.index}
    {:reply, {:ok, board}, state}
  end

  @impl true
  def handle_call({:submit, player_id, score}, _from, state) do
    seq = state.seq

    case :ets.lookup(state.index, player_id) do
      [] ->
        insert_entry(state, player_id, score, seq)
        {:reply, :ok, %{state | seq: seq + 1}}

      [{^player_id, {old_neg, _old_seq, _old_pid} = old_key}] ->
        old_score = -old_neg

        if score > old_score do
          :ets.delete(state.entries, old_key)
          insert_entry(state, player_id, score, seq)
          {:reply, :ok, %{state | seq: seq + 1}}
        else
          {:reply, :ok, state}
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp insert_entry(state, player_id, score, seq) do
    key = {-score, seq, player_id}
    :ets.insert(state.entries, {key, player_id, score})
    :ets.insert(state.index, {player_id, key})
    :ok
  end

  defp take_first(_tid, :"$end_of_table", _n, acc), do: Enum.reverse(acc)
  defp take_first(_tid, _key, 0, acc), do: Enum.reverse(acc)

  defp take_first(tid, key, n, acc) do
    [{^key, player_id, score}] = :ets.lookup(tid, key)
    take_first(tid, :ets.next(tid, key), n - 1, [{player_id, score} | acc])
  end
end
```

Give me only the complete implementation of `top` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
