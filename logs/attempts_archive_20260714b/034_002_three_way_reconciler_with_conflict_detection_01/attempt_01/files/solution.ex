defmodule ThreeWayReconciler do
  @moduledoc """
  Three-way reconciliation of record lists.

  Compares a common ancestor (`base`) against two edited versions (`left` and
  `right`) and, field by field, decides which changes merge cleanly and which
  genuinely conflict — the same shape of decision a version-control system makes
  during a merge.

  ## Example

      base  = [%{id: 1, name: "Alice", role: "user"}]
      left  = [%{id: 1, name: "Alicia", role: "user"}]
      right = [%{id: 1, name: "Alice", role: "admin"}]

      ThreeWayReconciler.reconcile(base, left, right, key_fields: [:id])
      #=> %{
      #=>   merged: [%{
      #=>     base:  %{id: 1, name: "Alice",  role: "user"},
      #=>     left:  %{id: 1, name: "Alicia", role: "user"},
      #=>     right: %{id: 1, name: "Alice",  role: "admin"},
      #=>     merged: %{id: 1, name: "Alicia", role: "admin"}
      #=>   }],
      #=>   conflicts: [],
      #=>   unpaired: []
      #=> }
  """

  @type record :: map()
  @type conflict_map :: %{optional(atom()) => %{base: term(), left: term(), right: term()}}

  @type merged_entry :: %{base: record(), left: record(), right: record(), merged: record()}
  @type conflict_entry :: %{
          base: record(),
          left: record(),
          right: record(),
          conflicts: conflict_map()
        }
  @type unpaired_entry :: %{
          key: %{optional(atom()) => term()},
          sides: %{base: record() | nil, left: record() | nil, right: record() | nil}
        }

  @type result :: %{
          merged: [merged_entry()],
          conflicts: [conflict_entry()],
          unpaired: [unpaired_entry()]
        }

  @doc """
  Reconciles `base`, `left` and `right` lists of maps by the composite key in `opts`.

  ## Options

    * `:key_fields` (required) — list of atoms forming the composite match key.
    * `:compare_fields` (optional) — list of atoms to reconcile on paired records.
      Defaults to all non-key fields present in any of the three records.
  """
  @spec reconcile([record()], [record()], [record()], keyword()) :: result()
  def reconcile(base, left, right, opts)
      when is_list(base) and is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_opt = Keyword.get(opts, :compare_fields, nil)

    base_index = index_by(base, key_fields)
    left_index = index_by(left, key_fields)
    right_index = index_by(right, key_fields)

    all_keys =
      [base_index, left_index, right_index]
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    init = %{merged: [], conflicts: [], unpaired: []}

    Enum.reduce(all_keys, init, fn key, acc ->
      b = Map.get(base_index, key)
      l = Map.get(left_index, key)
      r = Map.get(right_index, key)

      if b && l && r do
        fields = resolve_compare_fields([b, l, r], key_fields, compare_opt)
        {merged_record, conflicts} = three_way_merge(b, l, r, fields)

        if map_size(conflicts) == 0 do
          entry = %{base: b, left: l, right: r, merged: merged_record}
          %{acc | merged: [entry | acc.merged]}
        else
          entry = %{base: b, left: l, right: r, conflicts: conflicts}
          %{acc | conflicts: [entry | acc.conflicts]}
        end
      else
        entry = %{key: key_map(key, key_fields), sides: %{base: b, left: l, right: r}}
        %{acc | unpaired: [entry | acc.unpaired]}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Applies the per-field three-way merge rule, returning {merged_record, conflicts}.
  # The merged record starts from `base` so excluded and non-compared fields survive.
  @spec three_way_merge(record(), record(), record(), [atom()]) :: {record(), conflict_map()}
  defp three_way_merge(base, left, right, fields) do
    Enum.reduce(fields, {base, %{}}, fn field, {merged, conflicts} ->
      bv = Map.get(base, field)
      lv = Map.get(left, field)
      rv = Map.get(right, field)

      cond do
        lv == rv -> {Map.put(merged, field, lv), conflicts}
        lv == bv -> {Map.put(merged, field, rv), conflicts}
        rv == bv -> {Map.put(merged, field, lv), conflicts}
        true -> {merged, Map.put(conflicts, field, %{base: bv, left: lv, right: rv})}
      end
    end)
  end

  @spec fetch_key_fields!(keyword()) :: [atom()]
  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, [_ | _] = fields} ->
        if Enum.all?(fields, &is_atom/1) do
          fields
        else
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

      {:ok, _} ->
        raise ArgumentError, ":key_fields must be a non-empty list of atoms"

      :error ->
        raise ArgumentError, "required option :key_fields is missing"
    end
  end

  @spec index_by([record()], [atom()]) :: %{tuple() => record()}
  defp index_by(records, key_fields) do
    Map.new(records, fn record -> {composite_key(record, key_fields), record} end)
  end

  @spec composite_key(record(), [atom()]) :: tuple()
  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  @spec key_map(tuple(), [atom()]) :: %{optional(atom()) => term()}
  defp key_map(key_tuple, key_fields) do
    key_fields
    |> Enum.zip(Tuple.to_list(key_tuple))
    |> Map.new()
  end

  @spec resolve_compare_fields([record()], [atom()], [atom()] | nil) :: [atom()]
  defp resolve_compare_fields(_records, _key_fields, compare_fields)
       when is_list(compare_fields),
       do: compare_fields

  defp resolve_compare_fields(records, key_fields, nil) do
    key_set = MapSet.new(key_fields)

    records
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_set, &1))
  end
end