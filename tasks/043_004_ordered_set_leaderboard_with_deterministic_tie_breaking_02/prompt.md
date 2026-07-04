# Fill-in-the-middle: implement `rank/2`

Implement the public `rank/2` function for `OrderedLeaderboard`. It takes a
`board` (a map holding the owning server plus the `entries` ordered-set table
and the `index` set table) and a `player_id`, and it must return the player's
**unique 1-based ordinal position** in the leaderboard order — score
descending, ties broken by earliest arrival — as `{:ok, rank, score}`, or
`{:error, :not_found}` if the player has never submitted a score.

`rank/2` must NOT call the GenServer; it reads the public ETS tables directly so
it stays lock-free. First look the player up in the `index` table (a `:set`
mapping `player_id` to its current composite key `{-score, seq, player_id}`). If
the lookup returns `[]`, return `{:error, :not_found}`. Otherwise, destructure
the stored composite key. Because the `entries` table is an `:ordered_set` keyed
by that composite tuple, the player's rank is one more than the number of
entries whose key sorts strictly before theirs: build an `:ets.select_count/2`
match spec over `entries` that counts rows whose first key element (the whole
composite key, matched via `:"$1"`) is `<` the player's key (use `{:const, key}`
to treat the tuple as a literal), then return `{:ok, count + 1, score}` where
`score` is the negated stored score.

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

  @doc """
  Returns the top `n` players as `{player_id, score}` tuples in leaderboard
  order.  Reads the ordered set directly in key order.
  """
  @spec top(board(), non_neg_integer()) :: [{player_id(), number()}]
  def top(_board, 0), do: []

  def top(board, n) when is_integer(n) and n > 0 do
    take_first(board.entries, :ets.first(board.entries), n, [])
  end

  @doc """
  Returns `{:ok, rank, score}` (unique 1-based ordinal position) or
  `{:error, :not_found}`.  Reads the ETS tables directly.
  """
  @spec rank(board(), player_id()) :: {:ok, pos_integer(), number()} | {:error, :not_found}
  def rank(board, player_id) do
    # TODO
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