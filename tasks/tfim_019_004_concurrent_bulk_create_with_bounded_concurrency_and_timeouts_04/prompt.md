# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule ConcurrentCatalogTest do
  use ExUnit.Case, async: false

  setup do
    case Process.whereis(ConcurrentCatalog) do
      nil -> :ok
      pid -> Agent.stop(pid)
    end

    {:ok, _pid} = ConcurrentCatalog.start_link()
    :ok
  end

  test "creates all valid items with results in original order" do
    items = [
      %{"name" => "Alpha", "price" => 10},
      %{"name" => "Beta", "price" => 20},
      %{"name" => "Gamma", "price" => 30}
    ]

    results = ConcurrentCatalog.bulk_create(items)
    assert length(results) == 3

    for {i, expected} <- [{0, "Alpha"}, {1, "Beta"}, {2, "Gamma"}] do
      assert {^i, :ok, item} = Enum.at(results, i)
      assert item.name == expected
      assert is_integer(item.id)
    end

    assert ConcurrentCatalog.count() == 3

    all = ConcurrentCatalog.all()
    assert is_list(all)
    assert length(all) == 3
    assert Enum.sort(Enum.map(all, & &1.name)) == ["Alpha", "Beta", "Gamma"]
    assert Enum.sort(Enum.map(all, & &1.price)) == [10, 20, 30]

    for item <- all do
      assert %{id: id, name: name, price: price} = item
      assert is_integer(id)
      assert is_binary(name)
      assert is_integer(price)
      assert ConcurrentCatalog.get(id) == item
    end
  end

  test "all/0 reflects the store contents and is empty initially" do
    assert ConcurrentCatalog.all() == []

    ConcurrentCatalog.bulk_create([%{"name" => "Solo", "price" => 7}])

    assert [%{id: id, name: "Solo", price: 7}] = ConcurrentCatalog.all()
    assert ConcurrentCatalog.get(id) == %{id: id, name: "Solo", price: 7}
  end

  test "reports validation errors per index and still creates the rest" do
    # TODO
  end

  test "never exceeds the configured concurrency bound" do
    items = for k <- 1..6, do: %{"name" => "n#{k}", "price" => k, "delay" => 40}

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 2, timeout_ms: 1000)

    assert Enum.all?(results, fn {_i, tag, _} -> tag == :ok end)
    assert ConcurrentCatalog.count() == 6
    assert length(ConcurrentCatalog.all()) == 6
    assert ConcurrentCatalog.peak() <= 2
    assert ConcurrentCatalog.peak() == 2
  end

  test "max_concurrency 1 runs serially" do
    items = for k <- 1..4, do: %{"name" => "n#{k}", "price" => k, "delay" => 10}

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 1, timeout_ms: 1000)

    assert Enum.all?(results, fn {_i, tag, _} -> tag == :ok end)
    assert ConcurrentCatalog.count() == 4
    assert ConcurrentCatalog.peak() == 1
  end

  test "items exceeding the timeout are reported as :timeout and not inserted" do
    items = [
      %{"name" => "fast", "price" => 1},
      %{"name" => "slow", "price" => 2, "delay" => 200},
      %{"name" => "fast2", "price" => 3}
    ]

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 3, timeout_ms: 60)

    assert {0, :ok, _} = Enum.at(results, 0)
    assert {1, :error, :timeout} = Enum.at(results, 1)
    assert {2, :ok, _} = Enum.at(results, 2)

    assert ConcurrentCatalog.count() == 2
    refute Enum.any?(ConcurrentCatalog.all(), fn item -> item.name == "slow" end)
  end

  test "insert failures are reported per index" do
    items = [
      %{"name" => "a", "price" => 1, "fail" => true},
      %{"name" => "b", "price" => 2}
    ]

    results = ConcurrentCatalog.bulk_create(items)

    assert {0, :error, :insert_failed} = Enum.at(results, 0)
    assert {1, :ok, _} = Enum.at(results, 1)
    assert ConcurrentCatalog.count() == 1
    assert [%{name: "b"}] = ConcurrentCatalog.all()
  end

  test "empty batch returns an empty list" do
    assert [] = ConcurrentCatalog.bulk_create([])
    assert ConcurrentCatalog.count() == 0
    assert ConcurrentCatalog.all() == []
  end
end
```
