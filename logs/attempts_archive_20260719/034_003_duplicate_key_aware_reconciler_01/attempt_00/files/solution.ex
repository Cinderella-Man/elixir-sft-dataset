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
  @type duplicate_entry :: %{
          key: map(),
          left_count: non_neg_integer(),
          right_count: non_neg_integer()
        }
  @type result :: %{
          matched: [%{left: record(), right: record(), differences: diff_map()}],
          only_in_left: [record()],
          only_in_right: [record()],
          duplicate_keys: [duplicate_entry()]
        }

  @doc """
  Reconciles `left` and `right` by the composite key in `opts`, flagging duplicate
  keys instead of collapsing them.
  """
  @spec reconcile([record()], [record()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields_opt = Keyword.get(opts, :compare_fields, nil)

    left_groups = group_by_key(left, key_fields)
    right_groups = group_by_key(right, key_fields)

    all_keys =
      MapSet.union(MapSet.new(Map.keys(left_groups)), MapSet.new(Map.keys(right_groups)))

    init = %{matched: [], only_in_left: [], only_in_right: [], duplicate_keys: []}

    Enum.reduce(all_keys, init, fn key, acc ->
      lrecs = Map.get(left_groups, key, [])
      rrecs = Map.get(right_groups, key, [])
      classify(acc, key, key_fields, lrecs, rrecs, compare_fields_opt)
    end)
  end

  # ---------------------------------------------------------------------------
  # Classification
  # ---------------------------------------------------------------------------

  defp classify(acc, key, key_fields, lrecs, rrecs, compare_fields_opt) do
    lcount = length(lrecs)
    rcount = length(rrecs)

    cond do
      lcount > 1 or rcount > 1 ->
        entry = %{key: key_map(key, key_fields), left_count: lcount, right_count: rcount}
        %{acc | duplicate_keys: [entry | acc.duplicate_keys]}

      lcount == 1 and rcount == 1 ->
        l = hd(lrecs)
        r = hd(rrecs)
        fields = resolve_compare_fields(l, r, key_fields, compare_fields_opt)
        entry = %{left: l, right: r, differences: diff(l, r, fields)}
        %{acc | matched: [entry | acc.matched]}

      lcount == 1 ->
        %{acc | only_in_left: [hd(lrecs) | acc.only_in_left]}

      true ->
        %{acc | only_in_right: [hd(rrecs) | acc.only_in_right]}
    end
  end

  # ---------------------------------------------------------------------------
  # Validation / key handling
  # ---------------------------------------------------------------------------

  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, fields} when is_list(fields) and fields != [] ->
        unless Enum.all?(fields, &is_atom/1) do
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

        fields

      {:ok, _} ->
        raise ArgumentError, ":key_fields must be a non-empty list of atoms"

      :error ->
        raise ArgumentError, "required option :key_fields is missing"
    end
  end

  defp group_by_key(records, key_fields) do
    Enum.group_by(records, &composite_key(&1, key_fields))
  end

  defp composite_key(record, key_fields) do
    key_fields |> Enum.map(&Map.get(record, &1)) |> List.to_tuple()
  end

  defp key_map(key_tuple, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key_tuple))
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Diffing
  # ---------------------------------------------------------------------------

  defp resolve_compare_fields(_l, _r, _key_fields, compare_fields)
       when is_list(compare_fields),
       do: compare_fields

  defp resolve_compare_fields(left, right, key_fields, nil) do
    key_set = MapSet.new(key_fields)

    (Map.keys(left) ++ Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_set, &1))
  end

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