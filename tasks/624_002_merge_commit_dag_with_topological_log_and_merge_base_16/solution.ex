  @spec do_log(map(), hash()) :: {:ok, [entry()]} | {:error, :not_found}
  defp do_log(objects, start) do
    if Map.has_key?(objects, start) do
      {order, _visited} = dfs_post(start, objects, [], MapSet.new())
      {:ok, Enum.map(order, &entry(&1, objects))}
    else
      {:error, :not_found}
    end
  end