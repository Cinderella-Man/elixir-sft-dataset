  def pmap(collection, func, opts) when is_function(func, 1) and is_list(opts) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 5)
    timeout = Keyword.get(opts, :timeout, 5000)
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    unless is_integer(max_concurrency) and max_concurrency >= 1,
      do: raise(ArgumentError, ":max_concurrency must be a positive integer")

    unless is_integer(timeout) and timeout >= 0,
      do: raise(ArgumentError, ":timeout must be a non-negative integer")

    unless is_integer(max_attempts) and max_attempts >= 1,
      do: raise(ArgumentError, ":max_attempts must be a positive integer")

    indexed =
      collection
      |> Enum.to_list()
      |> Enum.with_index()
      |> Enum.map(fn {elem, idx} -> {elem, idx, max_attempts} end)

    total = length(indexed)

    if total == 0 do
      []
    else
      cfg = %{func: func, timeout: timeout}
      {seed, queue} = Enum.split(indexed, max_concurrency)

      running =
        Enum.reduce(seed, %{}, fn {elem, idx, attempts}, acc ->
          {ref, entry} = start_attempt(self(), func, elem, idx, attempts, timeout)
          Map.put(acc, ref, entry)
        end)

      results = loop(running, queue, cfg, %{})
      Enum.map(0..(total - 1), &Map.fetch!(results, &1))
    end
  end