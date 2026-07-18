  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency >= 1 do
    indexed = collection |> Enum.to_list() |> Enum.with_index()

    if indexed == [] do
      {:ok, []}
    else
      parent = self()
      {seed, queue} = Enum.split(indexed, max_concurrency)

      running =
        Map.new(seed, fn {elem, idx} ->
          {ref, pid, mon} = spawn_task(parent, func, elem)
          {ref, {pid, mon, idx}}
        end)

      loop(running, queue, func, parent, %{})
    end
  end