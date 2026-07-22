defmodule LedgerReconciler do
  @moduledoc """
  Reconciles two lists of records using bag (multiset) semantics.

  Keys may repeat on either side. Reconciliation asks whether the two sides
  *balance* per key — either by number of rows, or by the sum of a numeric
  `:quantity_field`. This is the shape of an inventory or ledger reconciliation
  rather than a set diff.

  ## Example

      left  = [%{sku: "A", qty: 3}, %{sku: "A", qty: 2}]
      right = [%{sku: "A", qty: 5}]

      LedgerReconciler.reconcile(left, right, key_fields: [:sku], quantity_field: :qty)
      #=> %{
      #=>   balanced: [%{
      #=>     key: %{sku: "A"}, left_total: 5, right_total: 5,
      #=>     left: [%{sku: "A", qty: 3}, %{sku: "A", qty: 2}],
      #=>     right: [%{sku: "A", qty: 5}]
      #=>   }],
      #=>   discrepancies: []
      #=> }
  """

  @type record :: map()

  @type balanced_entry :: %{
          key: %{optional(atom()) => term()},
          left_total: number(),
          right_total: number(),
          left: [record()],
          right: [record()]
        }

  @type discrepancy_entry :: %{
          key: %{optional(atom()) => term()},
          left_total: number(),
          right_total: number(),
          delta: number(),
          left: [record()],
          right: [record()]
        }

  @type result :: %{balanced: [balanced_entry()], discrepancies: [discrepancy_entry()]}

  @doc """
  Reconciles `left` and `right` by summed/counted totals per composite key.

  ## Options

    * `:key_fields` (required) — list of atoms forming the composite grouping key.
    * `:quantity_field` (optional) — atom whose values are summed per key. When
      omitted, the total is the record count per key. Missing values count as `0`.
  """
  @spec reconcile([record()], [record()], keyword()) :: result()
  def reconcile(left, right, opts)
      when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    quantity_field = Keyword.get(opts, :quantity_field, nil)

    left_groups = group_by_key(left, key_fields)
    right_groups = group_by_key(right, key_fields)

    all_keys =
      (Map.keys(left_groups) ++ Map.keys(right_groups))
      |> Enum.uniq()

    Enum.reduce(all_keys, %{balanced: [], discrepancies: []}, fn key, acc ->
      lrecs = Map.get(left_groups, key, [])
      rrecs = Map.get(right_groups, key, [])
      lt = total(lrecs, quantity_field)
      rt = total(rrecs, quantity_field)

      entry = %{
        key: key_map(key, key_fields),
        left_total: lt,
        right_total: rt,
        left: lrecs,
        right: rrecs
      }

      if lt == rt do
        %{acc | balanced: [entry | acc.balanced]}
      else
        %{acc | discrepancies: [Map.put(entry, :delta, lt - rt) | acc.discrepancies]}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Sums the quantity field (missing -> 0), or counts rows when no field is given.
  @spec total([record()], atom() | nil) :: number()
  defp total(records, nil), do: length(records)

  defp total(records, field) do
    Enum.reduce(records, 0, fn record, sum -> sum + (Map.get(record, field) || 0) end)
  end

  @spec group_by_key([record()], [atom()]) :: %{tuple() => [record()]}
  defp group_by_key(records, key_fields) do
    Enum.group_by(records, &composite_key(&1, key_fields))
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

  @spec fetch_key_fields!(keyword()) :: [atom()]
  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, fields} when is_list(fields) and fields != [] ->
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
end