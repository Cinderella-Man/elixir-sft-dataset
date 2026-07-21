# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule ConcurrentCatalog do
  def start_link(_ \\ []) do
    Agent.start_link(
      fn -> %{items: %{}, next_id: 1, running_pids: MapSet.new(), peak: 0} end,
      name: __MODULE__
    )
  end

  def all, do: Agent.get(__MODULE__, fn %{items: items} -> Map.values(items) end)

  def count, do: Agent.get(__MODULE__, fn %{items: items} -> map_size(items) end)

  def get(id), do: Agent.get(__MODULE__, fn %{items: items} -> Map.get(items, id) end)

  def peak, do: Agent.get(__MODULE__, fn %{peak: peak} -> peak end)

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
    case attrs["name"] do
      n when is_binary(n) and byte_size(n) > 0 ->
        if String.length(n) <= 100,
          do: errors,
          else: Map.put(errors, "name", ["should be at most 100 character(s)"])

      _ ->
        Map.put(errors, "name", ["can't be blank"])
    end
  end

  defp put_price_error(errors, attrs) do
    case attrs["price"] do
      p when is_integer(p) and p > 0 -> errors
      _ -> Map.put(errors, "price", ["must be a positive integer"])
    end
  end

  # -- store + concurrency tracking ----------------------------------------

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

  defp track_end do
    caller = self()

    Agent.update(__MODULE__, fn st ->
      %{st | running_pids: MapSet.delete(st.running_pids, caller)}
    end)
  end
end
```
