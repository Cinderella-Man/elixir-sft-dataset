  defp update_duration(acc, path, duration_ms) do
    acc = %{acc | duration_sum: acc.duration_sum + duration_ms}

    case acc.max_duration do
      nil ->
        %{acc | max_duration: {path, duration_ms}}

      {existing_path, existing_dur} ->
        cond do
          duration_ms > existing_dur ->
            %{acc | max_duration: {path, duration_ms}}

          duration_ms == existing_dur and path < existing_path ->
            %{acc | max_duration: {path, duration_ms}}

          true ->
            acc
        end
    end
  end