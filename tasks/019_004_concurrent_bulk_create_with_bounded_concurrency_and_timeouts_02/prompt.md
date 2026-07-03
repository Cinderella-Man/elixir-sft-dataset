Implement the public `bulk_create/2` function. It takes a list of attribute maps and
an optional keyword list `opts`. Read `opts[:max_concurrency]` (default `4`) and
`opts[:timeout_ms]` (default `1000`). Pair each item with its zero-based index using
`Enum.with_index/1`, then run the items through `Task.async_stream/3` calling
`process(attrs, i)` for each `{attrs, i}` pair, passing `max_concurrency: max`,
`timeout: timeout`, `on_timeout: :kill_task`, and `ordered: true` so that work
parallelizes but results stay in original input order. Re-attach an index to each
stream element with `Enum.with_index/1`, then map over the results: for a
`{:ok, result}` element return the `result` (already an index-aware tuple produced by
`process/2`), and for a `{:exit, :timeout}` element return `{idx, :error, :timeout}`
using the re-attached index. Return the plain list of result tuples with no
`{:ok, _}`/`{:error, _}` wrapper.

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
      fn -> %{items: %{}, next_id: 1, running: 0, peak: 0} end,
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
    # TODO
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

  @spec validate(map()) :: {:ok, %{name: String.t(), price: integer()}} | {:error, map()}
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

  @spec track_start() :: :ok
  defp track_start do
    Agent.update(__MODULE__, fn st ->
      running = st.running + 1
      %{st | running: running, peak: max(st.peak, running)}
    end)
  end

  @spec track_end() :: :ok
  defp track_end do
    Agent.update(__MODULE__, fn st -> %{st | running: st.running - 1} end)
  end
end
```