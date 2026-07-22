defmodule OrderedLeaderboard do
  @moduledoc """
  An all-time-high leaderboard backed by ETS with deterministic tie-breaking and
  unique ordinal ranks.

  ## Design

  The main store is an ETS `:ordered_set` keyed by the composite tuple

      {negated_score, sequence, player_id}

  Because ETS orders `:ordered_set` keys by Erlang term order, negating the score
  makes higher scores sort first, and the monotonically increasing `sequence`
  breaks ties in favour of whoever reached that score first. The trailing
  `player_id` only guards against duplicate keys; sequences are already unique.

  A secondary ETS `:set` maps `player_id -> composite_key` so an update can find
  and delete the player's previous entry in constant time.

  A `GenServer` owns both tables and serializes every write, handing out the
  sequence numbers so tie-breaking stays globally consistent. Reads (`top/2` and
  `rank/2`) never touch the server: both tables are `:public`, so lookups and
  ordered traversals run lock-free in the calling process.

  Only a player's all-time highest score is retained. A strictly higher score
  replaces the old entry and is treated as being "reached" at submission time
  (receiving a fresh sequence number); a lower or equal score is ignored.

  Note that ranks are *ordinal*: tied scores receive distinct, deterministic
  positions rather than shared competition ranks.

  ## Example

      {:ok, board} = OrderedLeaderboard.new(:arcade)
      :ok = OrderedLeaderboard.submit_score(board, "ada", 100)
      :ok = OrderedLeaderboard.submit_score(board, "grace", 100)
      OrderedLeaderboard.top(board, 2)
      #=> [{"ada", 100}, {"grace", 100}]
      OrderedLeaderboard.rank(board, "grace")
      #=> {:ok, 2, 100}
  """

  use GenServer

  @enforce_keys [:server, :table, :index]
  defstruct [:server, :table, :index]

  @type t :: %__MODULE__{server: GenServer.server(), table: :ets.tab(), index: :ets.tab()}
  @type player_id :: term()
  @type score :: number()
  @type key :: {number(), non_neg_integer(), player_id()}

  # -- Public API ------------------------------------------------------------

  @doc """
  Creates a new leaderboard whose main ETS table is named `board_name`.

  The secondary player index is named `:"#{board_name}_index"`. Returns
  `{:ok, board}`, where `board` is the handle to pass to the other functions.
  """
  @spec new(atom()) :: {:ok, t()} | {:error, term()}
  def new(board_name) when is_atom(board_name) do
    case GenServer.start_link(__MODULE__, board_name) do
      {:ok, pid} ->
        {:ok,
         %__MODULE__{
           server: pid,
           table: board_name,
           index: index_name(board_name)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Submits `score` for `player_id`, keeping only the player's all-time high.

  A strictly higher score replaces any previous entry and is timestamped with a
  fresh sequence number, so the player sorts behind others already tied at that
  score. A lower or equal score is a no-op. Always returns `:ok`.
  """
  @spec submit_score(t(), player_id(), score()) :: :ok
  def submit_score(%__MODULE__{server: server}, player_id, score) when is_number(score) do
    GenServer.call(server, {:submit_score, player_id, score})
  end

  @doc """
  Returns up to `n` players as `{player_id, score}` tuples in leaderboard order.

  Order is score descending, ties broken by earliest arrival at that score. The
  ordered set is traversed in key order and stops after `n` entries; fewer than
  `n` entries are returned when the board is smaller. A non-positive `n` yields
  an empty list.
  """
  @spec top(t(), integer()) :: [{player_id(), score()}]
  def top(%__MODULE__{table: table}, n) when is_integer(n) do
    if n <= 0 do
      []
    else
      table
      |> :ets.first()
      |> collect_top(table, n, [])
    end
  end

  @doc """
  Returns `{:ok, rank, score}` for `player_id`, or `{:error, :not_found}`.

  `rank` is the player's unique 1-based ordinal position in the total order
  (score descending, then arrival ascending). Tied scores receive distinct,
  deterministic ranks rather than a shared competition rank.
  """
  @spec rank(t(), player_id()) :: {:ok, pos_integer(), score()} | {:error, :not_found}
  def rank(%__MODULE__{table: table, index: index}, player_id) do
    case :ets.lookup(index, player_id) do
      [{^player_id, {_neg, _seq, _pid} = key}] ->
        {:ok, count_before(table, key, 1), score_of(key)}

      [] ->
        {:error, :not_found}
    end
  end

  # -- GenServer callbacks ---------------------------------------------------

  @impl GenServer
  def init(board_name) do
    table = :ets.new(board_name, [:ordered_set, :public, :named_table, read_concurrency: true])

    index =
      :ets.new(index_name(board_name), [:set, :public, :named_table, read_concurrency: true])

    {:ok, %{table: table, index: index, seq: 0}}
  end

  @impl GenServer
  def handle_call({:submit_score, player_id, score}, _from, state) do
    case :ets.lookup(state.index, player_id) do
      [{^player_id, old_key}] ->
        if score > score_of(old_key) do
          :ets.delete(state.table, old_key)
          {:reply, :ok, insert(state, player_id, score)}
        else
          {:reply, :ok, state}
        end

      [] ->
        {:reply, :ok, insert(state, player_id, score)}
    end
  end

  # -- Internals -------------------------------------------------------------

  @spec insert(map(), player_id(), score()) :: map()
  defp insert(state, player_id, score) do
    seq = state.seq + 1
    key = {negate(score), seq, player_id}
    :ets.insert(state.table, {key, player_id, score})
    :ets.insert(state.index, {player_id, key})
    %{state | seq: seq}
  end

  # Negation that avoids producing a bare `-0.0`/`+0.0` mismatch in comparisons:
  # term order treats 0 and 0.0 as equal, and `0 - 0.0` is `+0.0`, so plain
  # subtraction is already well behaved for both integers and floats.
  @spec negate(score()) :: number()
  defp negate(score), do: 0 - score

  @spec score_of(key()) :: score()
  defp score_of({neg_score, _seq, _player_id}), do: 0 - neg_score

  @spec collect_top(key() | :"$end_of_table", :ets.tab(), non_neg_integer(), [
          {player_id(), score()}
        ]) :: [{player_id(), score()}]
  defp collect_top(:"$end_of_table", _table, _remaining, acc), do: Enum.reverse(acc)
  defp collect_top(_key, _table, 0, acc), do: Enum.reverse(acc)

  defp collect_top(key, table, remaining, acc) do
    case :ets.lookup(table, key) do
      [{^key, player_id, score}] ->
        collect_top(:ets.next(table, key), table, remaining - 1, [{player_id, score} | acc])

      [] ->
        collect_top(:ets.next(table, key), table, remaining, acc)
    end
  end

  # Walks backwards from the player's key to the head of the table, counting the
  # entries that outrank it. Ordinal rank = 1 + number of strictly-earlier keys.
  @spec count_before(:ets.tab(), key(), pos_integer()) :: pos_integer()
  defp count_before(table, key, acc) do
    case :ets.prev(table, key) do
      :"$end_of_table" -> acc
      prev -> count_before(table, prev, acc + 1)
    end
  end

  @spec index_name(atom()) :: atom()
  defp index_name(board_name), do: :"#{board_name}_index"
end