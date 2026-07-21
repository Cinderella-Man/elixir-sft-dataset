  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) :: [term()]
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency >= 1 do
    indexed = collection |> Enum.to_list() |> Enum.with_index()
    total = length(indexed)

    if total == 0 do
      []
    else
      # `Task.async` links each task to this process; trap exits so an
      # abnormally exiting task delivers a message instead of killing us,
      # then restore the flag and drain those messages before returning.
      was_trapping? = Process.flag(:trap_exit, true)

      try do
        {seed, queue} = Enum.split(indexed, max_concurrency)

        # running: %{%Task{} => original_index}
        running = Map.new(seed, fn {elem, idx} -> {start_task(func, elem), idx} end)

        raw = collect(running, queue, func, _results = %{})

        # Reassemble in original order.
        Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
      after
        Process.flag(:trap_exit, was_trapping?)
        flush_exit_messages()
      end
    end
  end
