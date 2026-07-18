  defp maybe_update_errors(acc, "error", message, dt) do
    acc
    |> Map.update!(:error_messages, fn msgs ->
      Map.update(msgs, message, 1, &(&1 + 1))
    end)
    |> Map.update!(:errors_per_hour, fn eph ->
      bucket = hour_bucket(dt)
      Map.update(eph, bucket, 1, &(&1 + 1))
    end)
  end

  defp maybe_update_errors(acc, _level, _message, _dt), do: acc