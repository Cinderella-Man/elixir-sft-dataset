# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`rank/2` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `rank/2`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `rank/2` missing

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
  # TODO: @spec
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
