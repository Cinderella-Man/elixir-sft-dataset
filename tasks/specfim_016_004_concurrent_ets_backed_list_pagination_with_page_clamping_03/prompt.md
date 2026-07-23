# Fill in one @spec

Below: a working module where the `@spec` for
`insert/2` has been removed (see the `# TODO: @spec` marker).
Provide exactly that typespec, consistent with the implementation's
arguments, guards, and all reachable return shapes. No other edits.

## The module with the `@spec` for `insert/2` missing

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
  # TODO: @spec
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

The `@spec` attribute only — nothing more.
