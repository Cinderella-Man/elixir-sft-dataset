defmodule Reconciler do
  @moduledoc """
  Reconciles two lists of records by a composite key, producing a structured diff,
  with configurable per-field comparison semantics (tolerance, case-insensitive,
  custom predicates) instead of strict value equality.

  ## Example

      left  = [%{id: 1, name: "Alice", price: 10.0}]
      right = [%{id: 1, name: "ALICE", price: 10.1}]

      Reconciler.reconcile(left, right,
        key_fields: [:id],
        comparators: %{name: :case_insensitive, price: {:tolerance, 0.2}}
      )
      #=> %{matched: [%{left: ..., right: ..., differences: %{}}],
      #=>   only_in_left: [], only_in_right: []}
  """

  @type record :: map()
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}
  @type rule ::
          :exact
          | :case_insensitive
          | {:tolerance, number()}
          | (term(), term() -> boolean())

  @type result :: %{
          matched: [%{left: record(), right: record(), differences: diff_map()}],
          only_in_left: [record()],
          only_in_right: [record()]
        }

  @doc """
  Reconciles `left` and `right` by the composite key in `opts`, applying per-field
  comparison rules from `:comparators` (defaulting to exact `==`).
  """
  @spec reconcile([record()], [record()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields_opt = Keyword.get(opts, :compare_fields, nil)
    comparators = Keyword.get(opts, :comparators, %{})
    validate_comparators!(comparators)

    left_index = index_by(left, key_fields)
    right_index = index_by(right, key_fields)

    left_keys = MapSet.new(Map.keys(left_index))
    right_keys = MapSet.new(Map.keys(right_index))

    matched =
      left_keys
      |> MapSet.intersection(right_keys)
      |> Enum.map(fn key ->
        l = Map.fetch!(left_index, key)
        r = Map.fetch!(right_index, key)
        fields = resolve_compare_fields(l, r, key_fields, compare_fields_opt)
        %{left: l, right: r, differences: diff(l, r, fields, comparators)}
      end)

    only_in_left =
      left_keys |> MapSet.difference(right_keys) |> Enum.map(&Map.fetch!(left_index, &1))

    only_in_right =
      right_keys |> MapSet.difference(left_keys) |> Enum.map(&Map.fetch!(right_index, &1))

    %{matched: matched, only_in_left: only_in_left, only_in_right: only_in_right}
  end

  # ---------------------------------------------------------------------------
  # Validation
  # ---------------------------------------------------------------------------

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

  defp validate_comparators!(comparators) when is_map(comparators), do: :ok

  defp validate_comparators!(_),
    do: raise(ArgumentError, ":comparators must be a map of field => rule")

  # ---------------------------------------------------------------------------
  # Indexing / key handling
  # ---------------------------------------------------------------------------

  defp index_by(records, key_fields) do
    Map.new(records, fn record -> {composite_key(record, key_fields), record} end)
  end

  defp composite_key(record, key_fields) do
    key_fields |> Enum.map(&Map.get(record, &1)) |> List.to_tuple()
  end

  defp resolve_compare_fields(_l, _r, _key_fields, compare_fields)
       when is_list(compare_fields),
       do: compare_fields

  defp resolve_compare_fields(left, right, key_fields, nil) do
    key_set = MapSet.new(key_fields)

    (Map.keys(left) ++ Map.keys(right))
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(key_set, &1))
  end

  # ---------------------------------------------------------------------------
  # Diffing with per-field comparators
  # ---------------------------------------------------------------------------

  defp diff(left, right, fields, comparators) do
    Enum.reduce(fields, %{}, fn field, acc ->
      lv = Map.get(left, field)
      rv = Map.get(right, field)
      rule = Map.get(comparators, field, :exact)

      if equal?(lv, rv, rule) do
        acc
      else
        Map.put(acc, field, %{left: lv, right: rv})
      end
    end)
  end

  defp equal?(lv, rv, :exact), do: lv == rv

  defp equal?(lv, rv, :case_insensitive) when is_binary(lv) and is_binary(rv),
    do: String.downcase(lv) == String.downcase(rv)

  defp equal?(lv, rv, :case_insensitive), do: lv == rv

  defp equal?(lv, rv, {:tolerance, tol})
       when is_number(lv) and is_number(rv) and is_number(tol),
       do: abs(lv - rv) <= tol

  defp equal?(lv, rv, {:tolerance, _tol}), do: lv == rv

  defp equal?(lv, rv, fun) when is_function(fun, 2), do: fun.(lv, rv) == true
end