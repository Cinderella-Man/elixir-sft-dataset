  @spec run_check(term(), map()) :: map()
  defp run_check(name, probe) do
    old_level = probe.level

    {new_count, new_level, reason} =
      case probe.check_func.() do
        :ok ->
          {0, :ok, nil}

        {:error, reason} ->
          count = probe.fail_count + 1
          {count, level_for(count, probe.warn_after, probe.crit_after), reason}
      end

    if new_level != old_level do
      probe.on_change.(name, old_level, new_level, reason)
    end

    %{probe | fail_count: new_count, level: new_level}
  end