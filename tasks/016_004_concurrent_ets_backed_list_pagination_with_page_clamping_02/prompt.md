Implement the public `list/2` function. It performs offset pagination over a
point-in-time snapshot of the ETS table, ordered by id ascending.

First derive the effective parameters from `params`: compute `page_size` via
`parse_page_size/1` and the requested page via `parse_page/1`. Then take a
consistent snapshot of the table with `:ets.tab2list/1`, sort the entries by
their id (the key, `elem(&1, 0)`), and map each `{id, item}` tuple down to just
the stored `item`.

Compute `total_count` as the number of items and `total_pages` as
`ceil(total_count / page_size)` — but `0` when the catalog is empty. Determine
the effective `current` page with clamp-to-last-page semantics: if the catalog
is empty, `current` is `1`; if the requested page exceeds `total_pages`, clamp it
down to `total_pages`; otherwise use the requested page as-is.

Slice the page's items by dropping `(current - 1) * page_size` items and taking
`page_size` of them. Finally return `%{data: data, meta: %{...}}` where `meta`
carries `:requested_page` (the coerced requested page), `:current_page` (the
effective page served), `:page_size`, `:total_count`, and `:total_pages`.

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
    # TODO
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