  defp fill(running, [], _cfg), do: {running, []}

  defp fill(running, [{elem, idx, attempts} | rest], cfg) do
    {ref, entry} = start_attempt(self(), cfg.func, elem, idx, attempts, cfg.timeout)
    {Map.put(running, ref, entry), rest}
  end