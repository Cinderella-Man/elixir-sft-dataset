# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule EtsCatalog do
  @moduledoc """
  Offset pagination over a concurrent, `:public` `:ordered_set` ETS store.

  Reads materialize a point-in-time snapshot (sorted by id) so each `list/2`
  result is internally coherent under concurrent inserts. Requested pages beyond
  the end are clamped to the last page instead of returning an empty list.
  """

  @default_page 1
  @default_page_size 20
  @max_page_size 100

  @doc """
  Create and return a fresh `:ordered_set`, `:public` ETS table backing the
  catalog. Items are keyed by their integer id and other processes may insert
  concurrently.
  """
  @spec new() :: :ets.tid()
  def new do
    :ets.new(:ets_catalog, [:ordered_set, :public])
  end

  @doc """
  Insert `item` (a map with at least an integer `:id`) under its id. A later
  insert with the same id overwrites the earlier one. Returns `:ok`.
  """
  @spec insert(:ets.tid(), map()) :: :ok
  def insert(table, %{id: id} = item) do
    :ets.insert(table, {id, item})
    :ok
  end

  @doc """
  Return the number of stored items.
  """
  @spec count(:ets.tid()) :: non_neg_integer()
  def count(table), do: :ets.info(table, :size)

  @doc """
  Offset pagination over a point-in-time snapshot ordered by id ascending.

  `params` accepts optional string keys `"page"` (default `1`) and
  `"page_size"` (default `20`, clamped to `100`); invalid or out-of-range
  values fall back to their defaults. When the requested page exceeds
  `total_pages`, the page is clamped down to the last page (never an empty
  list). Returns `%{data: [...], meta: %{...}}`.
  """
  @spec list(:ets.tid(), map()) :: %{data: [map()], meta: map()}
  def list(table, params \\ %{}) do
    page_size = parse_page_size(params)
    requested = parse_page(params)

    all =
      table
      |> :ets.tab2list()
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(&elem(&1, 1))

    total_count = length(all)
    total_pages = if total_count == 0, do: 0, else: ceil(total_count / page_size)

    current =
      cond do
        total_count == 0 -> 1
        requested > total_pages -> total_pages
        true -> requested
      end

    data =
      all
      |> Enum.drop((current - 1) * page_size)
      |> Enum.take(page_size)

    %{
      data: data,
      meta: %{
        requested_page: requested,
        current_page: current,
        page_size: page_size,
        total_count: total_count,
        total_pages: total_pages
      }
    }
  end

  defp parse_page(%{"page" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> n
      _ -> @default_page
    end
  end

  defp parse_page(_), do: @default_page

  defp parse_page_size(%{"page_size" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_), do: @default_page_size
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule EtsCatalogTest do
  use ExUnit.Case, async: false

  defp seed(table, range) do
    for i <- range, do: EtsCatalog.insert(table, %{id: i, name: "Item #{i}"})
    table
  end

  test "returns first page ordered by id ascending" do
    table = EtsCatalog.new() |> seed(1..25)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page_size" => "10"})
    assert Enum.map(data, & &1.id) == Enum.to_list(1..10)
    assert meta.requested_page == 1
    assert meta.current_page == 1
    assert meta.page_size == 10
    assert meta.total_count == 25
    assert meta.total_pages == 3
  end

  test "later inserts overwrite same id and count reflects uniqueness" do
    table = EtsCatalog.new()
    EtsCatalog.insert(table, %{id: 1, name: "old"})
    EtsCatalog.insert(table, %{id: 1, name: "new"})

    assert EtsCatalog.count(table) == 1
    %{data: [item]} = EtsCatalog.list(table)
    assert item.name == "new"
  end

  test "clamps requested page beyond total to the last page and serves its items" do
    table = EtsCatalog.new() |> seed(1..5)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "99", "page_size" => "2"})
    assert Enum.map(data, & &1.id) == [5]
    assert meta.requested_page == 99
    assert meta.current_page == 3
    assert meta.total_pages == 3
    assert meta.total_count == 5
  end

  test "middle page returns the correct window" do
    table = EtsCatalog.new() |> seed(1..12)

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "2", "page_size" => "5"})
    assert Enum.map(data, & &1.id) == [6, 7, 8, 9, 10]
    assert meta.current_page == 2
  end

  test "empty catalog yields empty data, page 1, zero total_pages" do
    table = EtsCatalog.new()

    %{data: data, meta: meta} = EtsCatalog.list(table)
    assert data == []
    assert meta.current_page == 1
    assert meta.total_count == 0
    assert meta.total_pages == 0
  end

  test "clamps page_size and coerces bad page values" do
    table = EtsCatalog.new() |> seed(1..150)

    %{meta: meta} = EtsCatalog.list(table, %{"page_size" => "500", "page" => "-3"})
    assert meta.page_size == 100
    assert meta.requested_page == 1
    assert meta.current_page == 1
    assert meta.total_pages == 2
  end

  test "concurrent inserts from many processes are all reflected" do
    table = EtsCatalog.new()

    1..200
    |> Task.async_stream(
      fn i -> EtsCatalog.insert(table, %{id: i, name: "Item #{i}"}) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Enum.to_list()

    assert EtsCatalog.count(table) == 200

    %{data: data, meta: meta} = EtsCatalog.list(table, %{"page" => "2", "page_size" => "50"})
    assert meta.total_count == 200
    assert meta.total_pages == 4
    assert Enum.map(data, & &1.id) == Enum.to_list(51..100)
  end

  test "snapshot is internally coherent: data length never exceeds page_size" do
    # TODO
  end
end
```
