# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    items = [
      %{"name" => "", "price" => 10},
      %{"name" => "Good", "price" => 5},
      %{"name" => "Bad", "price" => -1}
    ]

    results = ConcurrentCatalog.bulk_create(items)

    assert {0, :error, {:validation, e0}} = Enum.at(results, 0)
    assert Map.has_key?(e0, "name")
    assert {1, :ok, _} = Enum.at(results, 1)
    assert {2, :error, {:validation, e2}} = Enum.at(results, 2)
    assert Map.has_key?(e2, "price")

    assert ConcurrentCatalog.count() == 1
    assert [%{name: "Good"}] = ConcurrentCatalog.all()
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

  test "a timing-out item still yields ordered per-index results while tasks overlap" do
    items = [
      %{"name" => "quick1", "price" => 1, "delay" => 20},
      %{"name" => "stuck", "price" => 2, "delay" => 600},
      %{"name" => "quick2", "price" => 3, "delay" => 20},
      %{"name" => "quick3", "price" => 4, "delay" => 20}
    ]

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 2, timeout_ms: 150)

    # Exactly one result per input item, in original input order.
    assert length(results) == 4
    assert Enum.map(results, fn {i, _tag, _reason} -> i end) == [0, 1, 2, 3]
    assert {0, :ok, %{name: "quick1"}} = Enum.at(results, 0)
    assert {1, :error, :timeout} = Enum.at(results, 1)
    assert {2, :ok, %{name: "quick2"}} = Enum.at(results, 2)
    assert {3, :ok, %{name: "quick3"}} = Enum.at(results, 3)

    # The killed item is never inserted; the surviving items all are.
    assert ConcurrentCatalog.count() == 3
    refute Enum.any?(ConcurrentCatalog.all(), fn item -> item.name == "stuck" end)

    # Work still parallelizes while the long-running item is in flight.
    assert ConcurrentCatalog.peak() >= 2
  end

  test "store stays consistent for later batches after a timed-out item is killed" do
    first =
      ConcurrentCatalog.bulk_create(
        [
          %{"name" => "gone", "price" => 5, "delay" => 600},
          %{"name" => "kept", "price" => 6}
        ],
        max_concurrency: 2,
        timeout_ms: 150
      )

    assert {0, :error, :timeout} = Enum.at(first, 0)
    assert {1, :ok, _} = Enum.at(first, 1)

    second =
      ConcurrentCatalog.bulk_create([
        %{"name" => "after1", "price" => 7},
        %{"name" => "after2", "price" => 8}
      ])

    assert Enum.all?(second, fn {_i, tag, _reason} -> tag == :ok end)
    assert ConcurrentCatalog.count() == 3

    # Every reported item is retrievable by its own id, across both batches.
    for {_i, :ok, item} <- first ++ second do
      assert ConcurrentCatalog.get(item.id) == item
    end

    assert Enum.sort(Enum.map(ConcurrentCatalog.all(), & &1.name)) ==
             ["after1", "after2", "kept"]

    assert ConcurrentCatalog.get(999_999) == nil
  end

  test "validation errors map the input string key to a list of message strings" do
    results =
      ConcurrentCatalog.bulk_create([
        %{"name" => "Priced wrong", "price" => 0},
        %{"name" => "", "price" => 3}
      ])

    assert {0, :error, {:validation, price_errors}} = Enum.at(results, 0)
    assert Map.keys(price_errors) == ["price"]
    assert [_ | _] = price_errors["price"]
    assert Enum.all?(price_errors["price"], &is_binary/1)

    assert {1, :error, {:validation, name_errors}} = Enum.at(results, 1)
    assert Map.keys(name_errors) == ["name"]
    assert [_ | _] = name_errors["name"]
    assert Enum.all?(name_errors["name"], &is_binary/1)

    assert ConcurrentCatalog.count() == 0
    assert ConcurrentCatalog.all() == []
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
