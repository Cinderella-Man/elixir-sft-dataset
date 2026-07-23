# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule CumulativeLeaderboard do
  def new(board_name) when is_atom(board_name) do
    tid =
      :ets.new(board_name, [
        :set,
        :public,
        :named_table,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, tid}
  end

  def add_points(board, player_id, points) when is_integer(points) do
    new_total = :ets.update_counter(board, player_id, points, {player_id, 0})
    {:ok, new_total}
  end

  def total(board, player_id) do
    case :ets.lookup(board, player_id) do
      [] -> {:error, :not_found}
      [{^player_id, score}] -> {:ok, score}
    end
  end

  def top(_board, 0), do: []

  def top(board, n) when is_integer(n) and n > 0 do
    board
    |> :ets.tab2list()
    |> Enum.sort_by(fn {_pid, score} -> score end, :desc)
    |> Enum.take(n)
  end

  def rank(board, player_id) do
    case :ets.lookup(board, player_id) do
      [] ->
        {:error, :not_found}

      [{^player_id, score}] ->
        match_spec = [{{:_, :"$1"}, [{:>, :"$1", score}], [true]}]
        above = :ets.select_count(board, match_spec)
        {:ok, above + 1, score}
    end
  end
end
```
