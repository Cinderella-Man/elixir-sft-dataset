# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule OrderedLeaderboard do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def new(board_name) when is_atom(board_name) do
    {:ok, pid} = GenServer.start_link(__MODULE__, board_name)
    GenServer.call(pid, :board)
  end

  def submit_score(board, player_id, score) when is_number(score) do
    GenServer.call(board.server, {:submit, player_id, score})
  end

  def top(_board, 0), do: []

  def top(board, n) when is_integer(n) and n > 0 do
    take_first(board.entries, :ets.first(board.entries), n, [])
  end

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
