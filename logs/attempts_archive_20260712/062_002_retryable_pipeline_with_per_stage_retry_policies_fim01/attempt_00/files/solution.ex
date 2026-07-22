  defp attempt(name, fun, value, retries_left, backoff, attempts_before, dur_acc) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)
    attempts = attempts_before + 1
    total_dur = dur_acc + duration

    case result do
      {:ok, next_value} ->
        {:ok, next_value, %{stage: name, duration_us: total_dur, attempts: attempts}}

      {:error, reason} ->
        if retries_left > 0 do
          if backoff > 0, do: Process.sleep(backoff)
          attempt(name, fun, value, retries_left - 1, backoff, attempts, total_dur)
        else
          {:error, name, reason, attempts}
        end

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}. " <>
                "Expected {:ok, result} or {:error, reason}."
    end
  end