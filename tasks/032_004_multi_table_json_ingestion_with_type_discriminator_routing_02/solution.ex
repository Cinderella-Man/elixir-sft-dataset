  @spec process_records(repo(), routing(), [map()], map()) :: stats()
  defp process_records(repo, routing, records, cfg) do
    total = length(records)
    type_field = cfg.type_field

    # Classify each record, preserving original order — and remember each
    # schema's FIRST appearance (reversed here), because a plain map cannot:
    # groups must later be processed in first-appearance order, not the
    # unspecified term order map iteration would give.
    {groups, order_rev, unroutable, missing_type} =
      Enum.reduce(records, {%{}, [], 0, 0}, fn record, {groups, order, unr, miss} ->
        case classify(record, type_field, routing) do
          :missing_type ->
            {groups, order, unr, miss + 1}

          :unroutable ->
            {groups, order, unr + 1, miss}

          {:ok, schema} ->
            order = if Map.has_key?(groups, schema), do: order, else: [schema | order]
            # Append to the group, maintaining insertion order.
            {Map.update(groups, schema, [record], &(&1 ++ [record])), order, unr, miss}
        end
      end)

    # Process each schema group, in the order the groups first appeared.
    by_schema =
      order_rev
      |> Enum.reverse()
      |> Enum.reduce(%{}, fn schema, acc ->
        schema_stats = insert_schema_group(repo, schema, Map.fetch!(groups, schema), cfg)
        Map.put(acc, schema, schema_stats)
      end)

    # Include schemas from routing that had zero records.
    by_schema =
      routing
      |> Map.values()
      |> Enum.uniq()
      |> Enum.reduce(by_schema, fn schema, acc ->
        Map.put_new(acc, schema, %{inserted: 0, failed: 0})
      end)

    %{
      total: total,
      by_schema: by_schema,
      unroutable: unroutable,
      missing_type: missing_type
    }
  end