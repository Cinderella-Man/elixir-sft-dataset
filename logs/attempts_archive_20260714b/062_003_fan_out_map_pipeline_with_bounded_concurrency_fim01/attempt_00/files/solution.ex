  defp run_stage({:seq, name, fun}, value) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)

    case result do
      {:ok, next_value} ->
        {:ok, next_value, %{stage: name, duration_us: duration, type: :sequential, count: 1}}

      {:error, reason} ->
        {:error, name, reason}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}."
    end
  end

  defp run_stage({:map, name, fun, mc_opt}, value) do
    unless is_list(value) do
      raise ArgumentError,
            "map stage #{inspect(name)} requires a list input, got: #{inspect(value)}"
    end

    count = length(value)
    max_concurrency = mc_opt || max(count, 1)

    {duration, results} =
      :timer.tc(fn ->
        value
        |> Task.async_stream(fun,
          max_concurrency: max_concurrency,
          ordered: true,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, element_result} -> element_result end)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        outputs = Enum.map(results, fn {:ok, v} -> v end)
        {:ok, outputs, %{stage: name, duration_us: duration, type: :map, count: count}}

      {:error, reason} ->
        {:error, name, reason}
    end
  end