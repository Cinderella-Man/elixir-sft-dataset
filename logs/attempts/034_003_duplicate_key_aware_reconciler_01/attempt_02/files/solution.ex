defmodule Reconciler do
  @moduledoc """
  Reconciles two lists of records by a composite key, producing a structured diff.

  Unlike a last-write-wins reconciler, any key that appears more than once on
  either side is treated as ambiguous and surfaced in a dedicated
  `:duplicate_keys` bucket rather than being silently collapsed. Only keys with
  exactly one record on each relevant side flow into `:matched`, `:only_in_left`,
  or `:only_in_right`.
  """

  @type record :: map()
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}
  @type matched_entry :: %{left: record(), right: record(), differences: diff_map()}
  @type duplicate_entry :: %{
          key: map(),
          left_count: non_neg_integer(),
          right_count: non_neg_integer()
        }
  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record()],
          only_in_right: [record()],
          duplicate_keys: [duplicate_entry()]
        }

  @doc """
  Reconciles `left` and `right` by the composite key in `opts`, flagging
  duplicate keys instead of collapsing them.

  Options:

    * `:key_fields` (required) — a non-empty list of atoms forming the
      composite key. Matching is exact.
    * `:compare_fields` (optional) — a list of atoms to diff on matched
      records. When omitted or `nil`, all fields except the key fields are
      compared. Missing fields are treated as `nil`.

  Returns a map with `:matched`, `:only_in_left`, `:only_in_right`, and
  `:duplicate_keys`. Result order is not significant.
  """
  @spec reconcile([record()], [record()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields = Keyword.get(opts, :compare_fields, nil)

    left_groups = group_by_key(left, key_fields)
    right_groups = group_by_key(right, key_fields)

    all_keys =
      MapSet.union(MapSet.new(Map.keys(left_groups)), MapSet.new(Map.keys(right_groups)))

    init = %{matched: [], only_in_left: [], only_in_right: [], duplicate_keys: []}

    Enum.reduce(all_keys, init, fn key, acc ->
      lrecs = Map.get(left_groups, key, [])
      rrecs = Map.get(right_groups, key, [])
      classify(acc, key, key_fields, lrecs, rrecs, compare_fields)
    end)
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  @spec classify(result(), tuple(), [atom()], [record()], [record()], [atom()] | nil) :: result()
  defp classify(acc, key, key_fields, lrecs, rrecs, compare_fields) do
    lcount = length(lrecs)
    rcount = length(rrecs)

    cond do
      lcount > 1 or rcount > 1 ->
        entry = %{key: key_map(key, key_fields), left_count: lcount, right_count: rcount}
        %{acc | duplicate_keys: [entry | acc.duplicate_keys]}

      lcount == 1 and rcount == 1 ->
        [l] = lrecs
        [r] = rrecs
        fields = resolve_compare_fields(l, r, key_fields, compare_fields)
        entry = %{left: l, right: r, differences: diff(l, r, fields)}
        %{acc | matched: [entry | acc.matched]}

      lcount == 1 ->
        [l] = lrecs
        %{acc | only_in_left: [l | acc.only_in_left]}

      true ->
        [r] = rrecs
        %{acc | only_in_right: [r | acc.only_in_right]}
    end
  end

  # ---------------------------------------------------------------------------
  # Validation / key handling
  # ---------------------------------------------------------------------------

  @spec fetch_key_fields!(keyword()) :: [atom(), ...]
  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, fields} when is_list(fields) and fields != [] ->
        if Enum.all?(fields, &is_atom/1) do
          fields
        else
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

      {:ok, _other} ->
        raise ArgumentError, ":key_fields must be a non-empty list of atoms"

      :error ->
        raise ArgumentError, "required option :key_fields is missing"
    end
  end

  @spec group_by_key([record()], [atom()]) :: %{optional(tuple()) => [record()]}
  defp group_by_key(records, key_fields) do
    Enum.group_by(records, &composite_key(&1, key_fields))
  end

  @spec composite_key(record(), [atom()]) :: tuple()
  defp composite_key(record, key_fields) do
    key_fields |> Enum.map(&Map.get(record, &1)) |> List.to_tuple()
  end

  @spec key_map(tuple(), [atom()]) :: map()
  defp key_map(key_tuple, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key_tuple))
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Diffing
  # ---------------------------------------------------------------------------

  @spec resolve_compare_fields(record(), record(), [atom()], [atom()] | nil) :: [atom()]
  defp resolve_compare_fields(_left, _right, _key_fields, compare_fields)
       when is_list(compare_fields),
       do: compare_fields

  defp resolve_compare_fields(left, right, key_fields, nil) do
    key_set = MapSet.new(key_fields)

    (Map.keys(left) ++ Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_set, &1))
  end

  @spec diff(record(), record(), [atom()]) :: diff_map()
  defp diff(left, right, fields) do
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
end