Implement the public `diff/3` function. It takes `old_list`, `new_list` (both lists of maps) and an `opts` keyword list, and returns an order-aware diff map with the keys `:added`, `:removed`, `:changed`, and `:moved`.

It should read the identifier field name from the `:key` option, defaulting to `:id`. Extract the id sequences of both lists and build `MapSet`s of the old and new ids. Compute `:added` as the whole records in `new_list` whose id is absent from the old set (in `new_list` order), and `:removed` as the whole records in `old_list` whose id is absent from the new set (in `old_list` order).

Using the private helpers, build lookup maps from id to record (`index_by/2`) for both lists and lookup maps from id to absolute 0-based position (`positions/2`) for both lists. Determine the id sequence of records common to both lists, in new order and in old order, and compute the set of stable anchor ids from the `lcs/2` of the old-order and new-order common sequences.

Produce `:changed` with one entry per common record (in `new_list` order) whose fields differ, using `diff_records/2`; skip records with no field differences; each kept entry is `%{key => id, changes: changes}`. Produce `:moved` with one entry per common record (in `new_list` order) that is not a stable anchor; each entry is `%{key => id, from: old_position, to: new_position}` using the position maps. Return `%{added: added, removed: removed, changed: changed, moved: moved}`.

```elixir
defmodule OrderedRecordDiff do
  @moduledoc """
  Order-aware diff of two record lists keyed by a unique ID field. In addition
  to `:added`, `:removed`, and field-level `:changed`, it reports `:moved`
  records whose relative order changed, using a Longest Common Subsequence of
  the common id sequences to identify the stable anchors.
  """

  @doc """
  Compares `old_list` and `new_list` (both lists of maps) and returns
  `%{added: [...], removed: [...], changed: [...], moved: [...]}`.

  Options:

    * `:key` — atom used as the unique record identifier (defaults to `:id`).
  """
  @spec diff([map()], [map()], keyword()) :: %{
          added: [map()],
          removed: [map()],
          changed: [map()],
          moved: [map()]
        }
  def diff(old_list, new_list, opts \\ []) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  defp positions(records, key) do
    records
    |> Enum.with_index()
    |> Map.new(fn {record, index} -> {Map.fetch!(record, key), index} end)
  end

  defp diff_records(old_record, new_record) do
    fields =
      (Map.keys(old_record) ++ Map.keys(new_record))
      |> Enum.uniq()

    Enum.reduce(fields, %{}, fn field, acc ->
      old_value = Map.get(old_record, field, :missing)
      new_value = Map.get(new_record, field, :missing)

      if old_value == new_value do
        acc
      else
        Map.put(acc, field, {old_value, new_value})
      end
    end)
  end

  # Longest Common Subsequence via bottom-up dynamic programming. On ties the
  # "skip in new" branch (j + 1) is preferred, keeping later new-sequence
  # elements as anchors.
  defp lcs(a_list, b_list) do
    a = List.to_tuple(a_list)
    b = List.to_tuple(b_list)
    n = tuple_size(a)
    m = tuple_size(b)

    indices = for i <- Enum.reverse(0..n), j <- Enum.reverse(0..m), do: {i, j}

    table =
      Enum.reduce(indices, %{}, fn {i, j}, table ->
        value =
          cond do
            i == n or j == m ->
              []

            elem(a, i) == elem(b, j) ->
              [elem(a, i) | Map.fetch!(table, {i + 1, j + 1})]

            true ->
              right = Map.fetch!(table, {i, j + 1})
              down = Map.fetch!(table, {i + 1, j})
              if length(right) >= length(down), do: right, else: down
          end

        Map.put(table, {i, j}, value)
      end)

    Map.fetch!(table, {0, 0})
  end
end
```