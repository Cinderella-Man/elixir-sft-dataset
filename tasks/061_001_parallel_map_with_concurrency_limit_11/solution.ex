  @doc """
  Maps `func` over `collection` in parallel, with at most `max_concurrency`
  tasks alive at any one time.

  ## Examples

      iex> ParallelMap.pmap(1..5, fn x -> x * 2 end, 2)
      [2, 4, 6, 8, 10]

      iex> ParallelMap.pmap([1, :boom, 3], fn
      ...>   :boom -> raise "oops"
      ...>   x    -> x * 10
      ...> end, 2)
      [10, {:error, _}, 30]
  """
  @spec pmap(Enumerable.t(), (term() -> term()), pos_integer()) :: [term()]
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency >= 1 do
    indexed = collection |> Enum.to_list() |> Enum.with_index()
    total = length(indexed)

    if total == 0 do
      []
    else
      parent = self()
      {seed, queue} = Enum.split(indexed, max_concurrency)

      # running: %{our_ref => {monitor_ref, original_index}}
      #
      # We use our own `make_ref()` as the primary key because it is the
      # value embedded in the result message that the spawned process sends
      # back.  The monitor ref is kept alongside so we can demonitor cleanly
      # after receiving the result.
      running =
        Map.new(seed, fn {elem, idx} ->
          {our_ref, mon_ref} = spawn_task(parent, func, elem)
          {our_ref, {mon_ref, idx}}
        end)

      raw = collect(running, queue, func, parent, _results = %{})

      # Reassemble in original order.
      Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
    end
  end