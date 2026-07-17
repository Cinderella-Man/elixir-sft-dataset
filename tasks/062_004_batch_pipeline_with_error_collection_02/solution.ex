  defp process_item([], value, stats), do: {:ok, value, stats}

  defp process_item([{{name, fun}, position} | rest], value, stats) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)
    stats = bump(stats, position, duration)

    case result do
      {:ok, next_value} ->
        process_item(rest, next_value, stats)

      {:error, reason} ->
        {:error, name, reason, stats}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}."
    end
  end