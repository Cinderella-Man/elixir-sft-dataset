# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule OrderedLeaderboardTest do
  use ExUnit.Case, async: false

  setup do
    name = :"oboard_#{:erlang.unique_integer([:positive])}"
    {:ok, board} = OrderedLeaderboard.new(name)
    %{board: board}
  end

  test "top is empty with no scores", %{board: board} do
    assert [] = OrderedLeaderboard.top(board, 5)
  end

  test "top is sorted by score descending", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 300)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 200)

    assert [{"alice", 300}, {"carol", 200}, {"bob", 100}] = OrderedLeaderboard.top(board, 3)
  end

  test "top(n) caps results and picks the highest", %{board: board} do
    for i <- 1..10, do: OrderedLeaderboard.submit_score(board, "p:#{i}", i * 10)
    assert [{"p:10", 100}, {"p:9", 90}, {"p:8", 80}] = OrderedLeaderboard.top(board, 3)
  end

  test "higher score overwrites, lower is a no-op", %{board: board} do
    # TODO
  end

  test "ties broken by who reached the score first", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 100)

    assert [{"alice", 100}, {"bob", 100}, {"carol", 100}] = OrderedLeaderboard.top(board, 3)
  end

  test "ranks are unique ordinals even on ties", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    OrderedLeaderboard.submit_score(board, "carol", 50)

    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100} = OrderedLeaderboard.rank(board, "bob")
    assert {:ok, 3, 50} = OrderedLeaderboard.rank(board, "carol")
  end

  test "reaching a new high re-timestamps arrival for tie-breaking", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    # alice and bob tied at 100, alice first -> alice ahead
    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)

    # bob jumps ahead, then both settle at 200 with bob reaching it first
    OrderedLeaderboard.submit_score(board, "bob", 200)
    OrderedLeaderboard.submit_score(board, "alice", 200)
    assert [{"bob", 200}, {"alice", 200}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 200} = OrderedLeaderboard.rank(board, "bob")
    assert {:ok, 2, 200} = OrderedLeaderboard.rank(board, "alice")
  end

  test "rank is :not_found for unknown player", %{board: board} do
    assert {:error, :not_found} = OrderedLeaderboard.rank(board, "ghost")
  end

  test "rank 1 for sole player", %{board: board} do
    OrderedLeaderboard.submit_score(board, "solo", 42)
    assert {:ok, 1, 42} = OrderedLeaderboard.rank(board, "solo")
  end

  test "zero and negative scores rank correctly", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", -10)
    OrderedLeaderboard.submit_score(board, "bob", -50)
    OrderedLeaderboard.submit_score(board, "carol", 0)

    assert [{"carol", 0}, {"alice", -10}, {"bob", -50}] = OrderedLeaderboard.top(board, 3)
    assert {:ok, 1, 0} = OrderedLeaderboard.rank(board, "carol")
    assert {:ok, 3, -50} = OrderedLeaderboard.rank(board, "bob")
  end

  test "different id types are independent", %{board: board} do
    OrderedLeaderboard.submit_score(board, "1", 100)
    OrderedLeaderboard.submit_score(board, 1, 200)
    OrderedLeaderboard.submit_score(board, :one, 300)

    assert {:ok, 1, 300} = OrderedLeaderboard.rank(board, :one)
    assert {:ok, 2, 200} = OrderedLeaderboard.rank(board, 1)
    assert {:ok, 3, 100} = OrderedLeaderboard.rank(board, "1")
  end

  test "two boards do not share state" do
    {:ok, a} = OrderedLeaderboard.new(:"oba_#{:erlang.unique_integer([:positive])}")
    {:ok, b} = OrderedLeaderboard.new(:"obb_#{:erlang.unique_integer([:positive])}")
    OrderedLeaderboard.submit_score(a, "alice", 999)
    assert {:error, :not_found} = OrderedLeaderboard.rank(b, "alice")
    assert [] = OrderedLeaderboard.top(b, 5)
  end

  test "large number of players ranked correctly", %{board: board} do
    for i <- 1..1_000, do: OrderedLeaderboard.submit_score(board, "player:#{i}", i)
    assert [{"player:1000", 1_000}] = OrderedLeaderboard.top(board, 1)
    assert {:ok, 1, 1_000} = OrderedLeaderboard.rank(board, "player:1000")
    assert {:ok, 1_000, 1} = OrderedLeaderboard.rank(board, "player:1")
  end

  test "resubmitting the exact same score does not re-timestamp arrival", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100)
    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)

    # equal is not "strictly higher", so alice must keep her earlier arrival slot
    OrderedLeaderboard.submit_score(board, "alice", 100)

    assert [{"alice", 100}, {"bob", 100}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100} = OrderedLeaderboard.rank(board, "bob")
  end

  test "float and integer scores of equal value tie and break by arrival", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 100)
    OrderedLeaderboard.submit_score(board, "bob", 100.0)

    assert [{"alice", 100}, {"bob", 100.0}] = OrderedLeaderboard.top(board, 2)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")
    assert {:ok, 2, 100.0} = OrderedLeaderboard.rank(board, "bob")

    # 100.0 is not strictly higher than 100, so it must not move alice
    OrderedLeaderboard.submit_score(board, "alice", 100.0)
    assert {:ok, 1, 100} = OrderedLeaderboard.rank(board, "alice")

    OrderedLeaderboard.submit_score(board, "alice", 100.5)
    assert [{"alice", 100.5}, {"bob", 100.0}] = OrderedLeaderboard.top(board, 2)
  end

  test "top returns every player when n exceeds the population", %{board: board} do
    OrderedLeaderboard.submit_score(board, "alice", 30)
    OrderedLeaderboard.submit_score(board, "bob", 20)

    assert [{"alice", 30}, {"bob", 20}] = OrderedLeaderboard.top(board, 50)
    assert [{"alice", 30}] = OrderedLeaderboard.top(board, 1)
  end
end
```
