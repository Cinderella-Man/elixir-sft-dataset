defmodule ConcurrentReconciler do
  @moduledoc """
  Reconciles two lists of record maps by a shared (possibly composite) key,
  producing a structured diff.

  Matched records are compared field-by-field, with the per-record field diffs
  computed concurrently across a pool of worker tasks (via `Task.async_stream`)
  so the work can take advantage of multiple schedulers. The result is identical
  in content to a sequential reconciliation; only the wall-clock cost differs.
  """

  @typedoc "A record represented as a map of field => value."
  @type record :: map()

  @typedoc "A diff map of field => %{left: value, right: value} for differing fields."
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}

  @typedoc "A matched entry carrying both original records and their differences."
  @type matched_entry :: %{left: record(), right: record(), differences: diff_map()}

  @typedoc "The full reconciliation result."
  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  @doc """
  Reconciles `left` and `right` (lists of maps) by the composite key given in
  `opts[:key_fields]`.

  Returns a map with `:matched`, `:only_in_left`, and `:only_in_right`.

  ## Options

    * `:key_fields` (required) — list of atoms forming the composite key.
    * `:compare_fields` (optional) — list of atoms to diff on matched records.
      Defaults to all fields except the key fields.
    * `:max_concurrency` (optional) — positive integer bounding parallel diffs.
      Defaults to `System.schedulers_online/0`.

  Raises `ArgumentError` if `:key_fields` is missing/invalid or if
  `:max_concurrency` is not a positive integer.
  """
  @spec reconcile([record()], [record()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields = Keyword.get(opts, :compare_fields, nil)
    max_concurrency = fetch_max_concurrency!(opts)

    left_index = index_by_key(left, key_fields)
    right_index = index_by_key(right, key_fields)

    left_keys = MapSet.new(Map.keys(left_index))
    right_keys = MapSet.new(Map.keys(right_index))

    common_keys = MapSet.intersection(left_keys, right_keys)
    only_left_keys = MapSet.difference(left_keys, right_keys)
    only_right_keys = MapSet.difference(right_keys, left_keys)

    matched =
      common_keys
      |> Task.async_stream(
        fn key ->
          l = Map.fetch!(left_index, key)
          r = Map.fetch!(right_index, key)
          %{left: l, right: r, differences: diff(l, r, key_fields, compare_fields)}
        end,
        max_concurrency: max_concurrency,
        ordered: false
      )
      |> Enum.map(&elem(&1, 1))

    %{
      matched: matched,
      only_in_left: Enum.map(only_left_keys, &Map.fetch!(left_index, &1)),
      only_in_right: Enum.map(only_right_keys, &Map.fetch!(right_index, &1))
    }
  end

  @spec fetch_key_fields!(keyword()) :: [atom()]
  defp fetch_key_fields!(opts) do
    case Keyword.get(opts, :key_fields) do
      [_ | _] = fields ->
        if Enum.all?(fields, &is_atom/1) do
          fields
        else
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

      _ ->
        raise ArgumentError, ":key_fields is required and must be a non-empty list of atoms"
    end
  end

  @spec fetch_max_concurrency!(keyword()) :: pos_integer()
  defp fetch_max_concurrency!(opts) do
    case Keyword.get(opts, :max_concurrency, System.schedulers_online()) do
      n when is_integer(n) and n > 0 -> n
      _ -> raise ArgumentError, ":max_concurrency must be a positive integer"
    end
  end

  @spec index_by_key([record()], [atom()]) :: %{optional(term()) => record()}
  defp index_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, key_for(record, key_fields), record)
    end)
  end

  @spec key_for(record(), [atom()]) :: [term()]
  defp key_for(record, key_fields), do: Enum.map(key_fields, &Map.get(record, &1))

  @spec diff(record(), record(), [atom()], [atom()] | nil) :: diff_map()
  defp diff(left, right, key_fields, compare_fields) do
    fields = fields_to_compare(left, right, key_fields, compare_fields)

    Enum.reduce(fields, %{}, fn field, acc ->
      lv = Map.get(left, field)
      rv = Map.get(right, field)

      if lv == rv do
        acc
      else
        Map.put(acc, field, %{left: lv, right: rv})
      end
    end)
  end

  @spec fields_to_compare(record(), record(), [atom()], [atom()] | nil) :: [atom()]
  defp fields_to_compare(_left, _right, _key_fields, compare_fields)
       when is_list(compare_fields) do
    compare_fields
  end

  defp fields_to_compare(left, right, key_fields, _compare_fields) do
    key_set = MapSet.new(key_fields)

    left
    |> Map.keys()
    |> Enum.concat(Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_set, &1))
  end
end