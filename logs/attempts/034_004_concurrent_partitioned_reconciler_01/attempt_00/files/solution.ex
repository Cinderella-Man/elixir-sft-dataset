defmodule Reconciler do
  @moduledoc """
  Reconciles record sets by a composite key. `reconcile/3` is the pure,
  single-dataset reconciler; `reconcile_all/2` reconciles many independent
  partitions concurrently via `Task.async_stream` and rolls the per-partition
  diffs up into a summary.

  Concurrency is an execution detail only: the output of `reconcile_all/2` is
  deterministic and independent of `:max_concurrency`.
  """

  @type record :: map()
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}
  @type single_result :: %{
          matched: [%{left: record(), right: record(), differences: diff_map()}],
          only_in_left: [record()],
          only_in_right: [record()]
        }
  @type partition :: %{
          required(:id) => term(),
          required(:left) => [record()],
          required(:right) => [record()]
        }
  @type all_result :: %{
          results: %{optional(term()) => single_result()},
          summary: %{matched: non_neg_integer(), only_in_left: non_neg_integer(), only_in_right: non_neg_integer()}
        }

  @doc """
  Reconciles a single `left`/`right` pair by the composite key in `opts`.
  """
  @spec reconcile([record()], [record()], keyword()) :: single_result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields_opt = Keyword.get(opts, :compare_fields, nil)
    do_reconcile(left, right, key_fields, compare_fields_opt)
  end

  @doc """
  Reconciles a list of partitions concurrently, returning per-partition results
  keyed by `:id` plus a roll-up `:summary`.
  """
  @spec reconcile_all([partition()], keyword()) :: all_result()
  def reconcile_all(partitions, opts) when is_list(partitions) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields_opt = Keyword.get(opts, :compare_fields, nil)
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

    results =
      partitions
      |> Task.async_stream(
        fn %{id: id, left: left, right: right} ->
          {id, do_reconcile(left, right, key_fields, compare_fields_opt)}
        end,
        max_concurrency: max_concurrency,
        ordered: true,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, pair} -> pair end)
      |> Map.new()

    %{results: results, summary: summarize(results)}
  end

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------

  defp summarize(results) do
    Enum.reduce(results, %{matched: 0, only_in_left: 0, only_in_right: 0}, fn {_id, r}, acc ->
      %{
        matched: acc.matched + length(r.matched),
        only_in_left: acc.only_in_left + length(r.only_in_left),
        only_in_right: acc.only_in_right + length(r.only_in_right)
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Pure per-partition reconciliation
  # ---------------------------------------------------------------------------

  defp do_reconcile(left, right, key_fields, compare_fields_opt) do
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
        %{left: l, right: r, differences: diff(l, r, fields)}
      end)

    only_in_left =
      left_keys |> MapSet.difference(right_keys) |> Enum.map(&Map.fetch!(left_index, &1))

    only_in_right =
      right_keys |> MapSet.difference(left_keys) |> Enum.map(&Map.fetch!(right_index, &1))

    %{matched: matched, only_in_left: only_in_left, only_in_right: only_in_right}
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