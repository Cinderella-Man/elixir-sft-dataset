defmodule ParallelReconciler do
  @moduledoc """
  A sharded, parallel reconciler for two lists of map records.

  `reconcile_parallel/3` partitions the composite key space into independent
  shards, reconciles each shard inside its own worker process, and composes the
  per-shard results into a single diff.

  Every record sharing a composite key is routed to the same shard via
  `:erlang.phash2/2`, so the reconciliation of any given key happens entirely
  within one shard. The shard count is purely a performance knob: the result is
  identical regardless of how many shards are used.

  The reconciler is resilient to misbehaving shards. A worker that exceeds its
  wall-clock budget is killed and recorded in `:timed_out_shards`; a worker that
  crashes because the user-supplied `:compare` callback raises is recorded in
  `:failed_shards`. In either case the shard contributes nothing to the diff and
  the other shards still complete and contribute their results.
  """

  @default_shards 4
  @default_timeout 5000

  @typedoc "A record is a map from atom field names to arbitrary values."
  @type rec :: map()

  @doc """
  Reconcile `left` and `right` (lists of maps) by a composite key, in parallel.

  Options:

    * `:key_fields` (required) — list of atoms forming the composite match key.
    * `:compare_fields` — list of atoms to diff on; defaults to every field in
      either record of a matched pair, minus the key fields.
    * `:shards` — positive integer, default `#{@default_shards}`.
    * `:timeout` — positive integer milliseconds per shard, default
      `#{@default_timeout}`.
    * `:compare` — `compare.(field, left_value, right_value)` returning truthy
      when equal; defaults to `==`.

  Returns a map with `:matched`, `:only_in_left`, `:only_in_right`,
  `:timed_out_shards`, and `:failed_shards`.
  """
  @spec reconcile_parallel([rec()], [rec()], keyword()) :: map()
  def reconcile_parallel(left, right, opts) do
    key_fields = validate_key_fields(opts)
    shards = validate_shards(opts)
    timeout = validate_timeout(opts)
    compare_fields = Keyword.get(opts, :compare_fields)
    compare = Keyword.get(opts, :compare) || fn _field, a, b -> a == b end

    left_by = group_by_shard(left, key_fields, shards)
    right_by = group_by_shard(right, key_fields, shards)

    active =
      MapSet.union(MapSet.new(Map.keys(left_by)), MapSet.new(Map.keys(right_by)))
      |> MapSet.to_list()

    workers = spawn_workers(active, left_by, right_by, key_fields, compare_fields, compare)

    deadline = System.monotonic_time(:millisecond) + timeout
    {results, failed, timed_out} = collect(workers, deadline, [], [], [])

    %{
      matched: Enum.flat_map(results, & &1.matched),
      only_in_left: Enum.flat_map(results, & &1.only_in_left),
      only_in_right: Enum.flat_map(results, & &1.only_in_right),
      timed_out_shards: timed_out |> Enum.uniq() |> Enum.sort(),
      failed_shards: failed |> Enum.uniq() |> Enum.sort()
    }
  end

  # --- Worker orchestration -------------------------------------------------

  @spec spawn_workers([non_neg_integer()], map(), map(), [atom()], [atom()] | nil, fun()) ::
          %{reference() => {non_neg_integer(), pid()}}
  defp spawn_workers(active, left_by, right_by, key_fields, compare_fields, compare) do
    parent = self()

    for shard <- active, into: %{} do
      l = Map.get(left_by, shard, [])
      r = Map.get(right_by, shard, [])

      {pid, ref} =
        spawn_monitor(fn ->
          res = process_shard(l, r, key_fields, compare_fields, compare)
          send(parent, {:shard_result, self(), shard, res})
        end)

      {ref, {shard, pid}}
    end
  end

  @spec collect(map(), integer(), [map()], [non_neg_integer()], [non_neg_integer()]) ::
          {[map()], [non_neg_integer()], [non_neg_integer()]}
  defp collect(workers, deadline, results, failed, timed_out) do
    if map_size(workers) == 0 do
      {results, failed, timed_out}
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:shard_result, _pid, shard, res} ->
          {ref, _} = Enum.find(workers, fn {_ref, {s, _pid}} -> s == shard end)
          Process.demonitor(ref, [:flush])
          collect(Map.delete(workers, ref), deadline, [res | results], failed, timed_out)

        {:DOWN, ref, :process, _pid, reason} ->
          case Map.get(workers, ref) do
            nil ->
              collect(workers, deadline, results, failed, timed_out)

            {_shard, _pid} when reason == :normal ->
              collect(Map.delete(workers, ref), deadline, results, failed, timed_out)

            {shard, _pid} ->
              collect(Map.delete(workers, ref), deadline, results, [shard | failed], timed_out)
          end
      after
        remaining ->
          tos =
            for {ref, {shard, pid}} <- workers do
              Process.exit(pid, :kill)
              Process.demonitor(ref, [:flush])
              shard
            end

          {results, failed, timed_out ++ tos}
      end
    end
  end

  # --- Per-shard reconciliation ---------------------------------------------

  @spec process_shard([rec()], [rec()], [atom()], [atom()] | nil, fun()) :: map()
  defp process_shard(left, right, key_fields, compare_fields, compare) do
    left_map = index_by_key(left, key_fields)
    right_map = index_by_key(right, key_fields)

    left_keys = MapSet.new(Map.keys(left_map))
    right_keys = MapSet.new(Map.keys(right_map))

    matched =
      for k <- MapSet.to_list(MapSet.intersection(left_keys, right_keys)) do
        lrec = Map.fetch!(left_map, k)
        rrec = Map.fetch!(right_map, k)
        diffs = compute_differences(lrec, rrec, key_fields, compare_fields, compare)
        %{left: lrec, right: rrec, differences: diffs}
      end

    only_left_keys = MapSet.difference(left_keys, right_keys)
    only_right_keys = MapSet.difference(right_keys, left_keys)

    %{
      matched: matched,
      only_in_left: for(k <- MapSet.to_list(only_left_keys), do: Map.fetch!(left_map, k)),
      only_in_right: for(k <- MapSet.to_list(only_right_keys), do: Map.fetch!(right_map, k))
    }
  end

  @spec compute_differences(rec(), rec(), [atom()], [atom()] | nil, fun()) :: map()
  defp compute_differences(lrec, rrec, key_fields, compare_fields, compare) do
    fields = compare_fields || default_fields(lrec, rrec, key_fields)

    Enum.reduce(fields, %{}, fn field, acc ->
      lv = Map.get(lrec, field)
      rv = Map.get(rrec, field)

      if compare.(field, lv, rv) do
        acc
      else
        Map.put(acc, field, %{left: lv, right: rv})
      end
    end)
  end

  @spec default_fields(rec(), rec(), [atom()]) :: [atom()]
  defp default_fields(lrec, rrec, key_fields) do
    (Map.keys(lrec) ++ Map.keys(rrec))
    |> Enum.uniq()
    |> Enum.reject(&(&1 in key_fields))
  end

  @spec index_by_key([rec()], [atom()]) :: %{tuple() => rec()}
  defp index_by_key(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      Map.put(acc, key_tuple(record, key_fields), record)
    end)
  end

  @spec group_by_shard([rec()], [atom()], pos_integer()) :: %{non_neg_integer() => [rec()]}
  defp group_by_shard(records, key_fields, shards) do
    Enum.group_by(records, fn record ->
      :erlang.phash2(key_tuple(record, key_fields), shards)
    end)
  end

  @spec key_tuple(rec(), [atom()]) :: tuple()
  defp key_tuple(record, key_fields) do
    key_fields |> Enum.map(&Map.get(record, &1)) |> List.to_tuple()
  end

  # --- Validation -----------------------------------------------------------

  @spec validate_key_fields(keyword()) :: [atom()]
  defp validate_key_fields(opts) do
    key_fields = Keyword.get(opts, :key_fields)

    cond do
      is_nil(key_fields) ->
        raise ArgumentError, ":key_fields is required and must be a non-empty list of atoms"

      not is_list(key_fields) ->
        raise ArgumentError, ":key_fields must be a list of atoms"

      key_fields == [] ->
        raise ArgumentError, ":key_fields must not be empty"

      not Enum.all?(key_fields, &is_atom/1) ->
        raise ArgumentError, ":key_fields must contain only atoms"

      true ->
        key_fields
    end
  end

  @spec validate_shards(keyword()) :: pos_integer()
  defp validate_shards(opts) do
    case Keyword.get(opts, :shards, @default_shards) do
      shards when is_integer(shards) and shards > 0 -> shards
      _ -> raise ArgumentError, ":shards must be a positive integer"
    end
  end

  @spec validate_timeout(keyword()) :: pos_integer()
  defp validate_timeout(opts) do
    case Keyword.get(opts, :timeout, @default_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _ -> raise ArgumentError, ":timeout must be a positive integer"
    end
  end
end
