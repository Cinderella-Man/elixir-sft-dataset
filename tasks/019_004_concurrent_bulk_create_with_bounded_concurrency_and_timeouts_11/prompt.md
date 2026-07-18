# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `put_name_error` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a self-contained Elixir context module `ConcurrentCatalog` that performs **concurrent bulk creation** of items into an in-memory store using a bounded concurrency pool, with per-item timeouts and index-aware result reporting that preserves the original input order.

This is a variation on a sequential bulk endpoint: here each item is validated and inserted concurrently (each item is independent, so this is always partial), but the number of items processed simultaneously is capped, and any item whose work exceeds a timeout is killed and reported as a timeout.

**Store**
- Back the module with a named `Agent` started via `ConcurrentCatalog.start_link/0` (registered under the module name).
- Provide `ConcurrentCatalog.all/0`, `ConcurrentCatalog.count/0`, `ConcurrentCatalog.get/1` (by id), and `ConcurrentCatalog.peak/0` (the high-water mark of simultaneously-running item tasks — for verifying the concurrency bound). `get/1` returns the stored item map directly, or `nil` when no item with that id exists.
- Each stored item is `%{id: integer, name: String.t(), price: integer}`.

**Input shape**
- Each attribute map: `"name"` (required, 1–100 chars), `"price"` (required integer > 0). Two optional test hooks simulate real work: `"delay"` (integer ms the insert takes) and `"fail"` (truthy → the insert fails).

**`ConcurrentCatalog.bulk_create(list_of_attrs, opts \\ [])`**
- `opts[:max_concurrency]` (default `4`) — at most this many item tasks run at once.
- `opts[:timeout_ms]` (default `1000`) — per-item time budget; an item exceeding it is killed.
- Process items concurrently (use `Task.async_stream/3` with `ordered: true`, `on_timeout: :kill_task`, and the given `max_concurrency`/`timeout`) so that CPU/IO-bound insert work parallelizes, yet the returned results are in **original input order**, exactly one per item.
- Each result carries the zero-based index: `{index, :ok, item}`, or `{index, :error, reason}` where `reason` is `{:validation, errors_map}`, `:insert_failed`, or `:timeout`. The `errors_map` maps the offending field's **string** key exactly as in the input attrs to a list of error message strings — e.g. `%{"price" => ["must be a positive integer"]}`.
- Return the plain list of results (no `{:ok, _}`/`{:error, _}` wrapper — every item is independent).

The store must remain consistent under concurrent access (Agent serializes writes), the running-task high-water mark must never exceed `max_concurrency`, and timed-out or failed items must not be inserted. Use only Elixir/OTP standard library — no external dependencies.

## The module with `put_name_error` missing

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

  defp put_name_error(errors, attrs) do
    # TODO
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

Give me only the complete implementation of `put_name_error` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
