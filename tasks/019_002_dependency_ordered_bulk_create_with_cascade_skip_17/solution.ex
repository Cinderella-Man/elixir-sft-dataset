  @doc """
  Bulk-create items with index-aware, dependency-aware result reporting.

  Modes:
    * default — all-or-nothing: any bad/cyclic item rolls back the whole batch.
    * `partial: true` — create creatable items; skip dependents of bad items.
  """
  @spec bulk_create([attrs()], keyword()) :: {:ok, [result()]} | {:error, [result()]}
  def bulk_create(list, opts \\ []) do
    partial? = Keyword.get(opts, :partial, false)
    n = length(list)
    indices = Enum.to_list(0..(n - 1)//1)
    attrs_by_index = list |> Enum.with_index() |> Map.new(fn {a, i} -> {i, a} end)

    # Reference index and duplicate detection. A ref declared more than once is
    # a `:duplicate_ref` error for each declaring item, but the ref itself is
    # still *known*: dependents point at the first declaring index so they are
    # reported as `:skipped` rather than `:unknown_parent`.
    refs = for i <- indices, r = attrs_by_index[i]["ref"], is_binary(r), do: {r, i}
    ref_groups = Enum.group_by(refs, fn {r, _} -> r end, fn {_, i} -> i end)

    dup_ref_indices =
      for {_r, is} <- ref_groups, length(is) > 1, i <- is, into: MapSet.new(), do: i

    ref_index = for {r, is} <- ref_groups, into: %{}, do: {r, Enum.min(is)}

    # Parent resolution.
    {parent_of, unknown_parent} =
      Enum.reduce(indices, {%{}, MapSet.new()}, fn i, {po, up} ->
        case attrs_by_index[i]["parent"] do
          nil ->
            {Map.put(po, i, nil), up}

          p when is_binary(p) ->
            case Map.fetch(ref_index, p) do
              {:ok, pi} when pi != i -> {Map.put(po, i, pi), up}
              {:ok, _self} -> {Map.put(po, i, i), up}
              :error -> {Map.put(po, i, nil), MapSet.put(up, i)}
            end

          _ ->
            {Map.put(po, i, nil), MapSet.put(up, i)}
        end
      end)

    # Per-item validation.
    val_errors = Map.new(indices, fn i -> {i, validate(attrs_by_index[i])} end)

    # Cycle membership (only nodes actually on a cycle).
    cyclic =
      for i <- indices, on_cycle?(i, parent_of), into: MapSet.new(), do: i

    bad_reason =
      Map.new(indices, fn i ->
        reason =
          cond do
            val_errors[i] != nil -> {:validation, val_errors[i]}
            MapSet.member?(dup_ref_indices, i) -> :duplicate_ref
            MapSet.member?(unknown_parent, i) -> :unknown_parent
            MapSet.member?(cyclic, i) -> :cycle
            true -> nil
          end

        {i, reason}
      end)

    status = Map.new(indices, fn i -> {i, status_of(i, parent_of, bad_reason)} end)

    creatable = for i <- indices, status[i] == :ok, into: MapSet.new(), do: i

    cond do
      partial? ->
        items = create_all(creatable, parent_of, attrs_by_index)
        {:ok, build_results(indices, status, items)}

      MapSet.size(creatable) == n ->
        items = create_all(creatable, parent_of, attrs_by_index)
        {:ok, build_results(indices, status, items)}

      true ->
        {:error, build_results(indices, status, %{})}
    end
  end