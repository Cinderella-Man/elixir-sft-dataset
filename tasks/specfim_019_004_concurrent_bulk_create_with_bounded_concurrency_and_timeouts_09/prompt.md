# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`validate/1` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `validate/1`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `validate/1` missing

```elixir
defmodule ConcurrentCatalog do
  @moduledoc """
  Concurrent bulk creation into an in-memory store with a bounded concurrency
  pool and per-item timeouts. Results are index-aware and preserve input order.

  The store is backed by a named `Agent` (registered under this module) and
  each stored item is `%{id: integer, name: String.t(), price: integer}`.
  """

  @type item :: %{id: pos_integer(), name: String.t(), price: integer()}
  @type reason :: {:validation, map()} | :insert_failed | :timeout
  @type result ::
          {non_neg_integer(), :ok, item()}
          | {non_neg_integer(), :error, reason()}

  @doc """
  Start the store `Agent`, registered under this module's name.
  """
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(_ \\ []) do
    Agent.start_link(
      fn -> %{items: %{}, next_id: 1, running_pids: MapSet.new(), peak: 0} end,
      name: __MODULE__
    )
  end

  @doc """
  Return all stored items.
  """
  @spec all() :: [item()]
  def all, do: Agent.get(__MODULE__, fn %{items: items} -> Map.values(items) end)

  @doc """
  Return the number of stored items.
  """
  @spec count() :: non_neg_integer()
  def count, do: Agent.get(__MODULE__, fn %{items: items} -> map_size(items) end)

  @doc """
  Fetch a stored item by `id`, or `nil` when absent.
  """
  @spec get(pos_integer()) :: item() | nil
  def get(id), do: Agent.get(__MODULE__, fn %{items: items} -> Map.get(items, id) end)

  @doc """
  Return the high-water mark of simultaneously-running item tasks.
  """
  @spec peak() :: non_neg_integer()
  def peak, do: Agent.get(__MODULE__, fn %{peak: peak} -> peak end)

  @doc """
  Concurrently create items. `opts[:max_concurrency]` (default 4),
  `opts[:timeout_ms]` (default 1000). Returns a list of index-aware result tuples.
  """
  @spec bulk_create([map()], keyword()) :: [result()]
  def bulk_create(list, opts \\ []) do
    max = Keyword.get(opts, :max_concurrency, 4)
    timeout = Keyword.get(opts, :timeout_ms, 1000)

    list
    |> Enum.with_index()
    |> Task.async_stream(
      fn {attrs, i} -> process(attrs, i) end,
      max_concurrency: max,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: true
    )
    |> Enum.with_index()
    |> Enum.map(fn
      {{:ok, result}, _idx} -> result
      {{:exit, :timeout}, idx} -> {idx, :error, :timeout}
    end)
  end

  # -- per-item work --------------------------------------------------------

  @spec process(map(), non_neg_integer()) :: result()
  defp process(attrs, i) do
    case validate(attrs) do
      {:error, errs} ->
        {i, :error, {:validation, errs}}

      {:ok, norm} ->
        track_start()

        try do
          delay = Map.get(attrs, "delay", 0)
          if is_integer(delay) and delay > 0, do: Process.sleep(delay)

          if Map.get(attrs, "fail", false) do
            {i, :error, :insert_failed}
          else
            {i, :ok, insert(norm.name, norm.price)}
          end
        after
          track_end()
        end
    end
  end

  # TODO: @spec
  defp validate(attrs) do
    errors =
      %{}
      |> put_name_error(attrs)
      |> put_price_error(attrs)

    if map_size(errors) == 0,
      do: {:ok, %{name: attrs["name"], price: attrs["price"]}},
      else: {:error, errors}
  end

  @spec put_name_error(map(), map()) :: map()
  defp put_name_error(errors, attrs) do
    case attrs["name"] do
      n when is_binary(n) and byte_size(n) > 0 ->
        if String.length(n) <= 100,
          do: errors,
          else: Map.put(errors, "name", ["should be at most 100 character(s)"])

      _ ->
        Map.put(errors, "name", ["can't be blank"])
    end
  end

  @spec put_price_error(map(), map()) :: map()
  defp put_price_error(errors, attrs) do
    case attrs["price"] do
      p when is_integer(p) and p > 0 -> errors
      _ -> Map.put(errors, "price", ["must be a positive integer"])
    end
  end

  # -- store + concurrency tracking ----------------------------------------

  @spec insert(String.t(), integer()) :: item()
  defp insert(name, price) do
    Agent.get_and_update(__MODULE__, fn %{items: items, next_id: id} = st ->
      item = %{id: id, name: name, price: price}
      {item, %{st | items: Map.put(items, id, item), next_id: id + 1}}
    end)
  end

  # Tracking must survive `on_timeout: :kill_task`: a brutally killed task
  # never reaches its `after track_end()`, so a plain counter leaks upward and
  # the reported peak could exceed `max_concurrency`. Tracking LIVE pids and
  # pruning dead ones before each count keeps the high-water mark honest.
  @spec track_start() :: :ok
  defp track_start do
    caller = self()

    Agent.update(__MODULE__, fn st ->
      pids =
        st.running_pids
        |> Enum.filter(&Process.alive?/1)
        |> MapSet.new()
        |> MapSet.put(caller)

      %{st | running_pids: pids, peak: max(st.peak, MapSet.size(pids))}
    end)
  end

  @spec track_end() :: :ok
  defp track_end do
    caller = self()

    Agent.update(__MODULE__, fn st ->
      %{st | running_pids: MapSet.delete(st.running_pids, caller)}
    end)
  end
end
```

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
