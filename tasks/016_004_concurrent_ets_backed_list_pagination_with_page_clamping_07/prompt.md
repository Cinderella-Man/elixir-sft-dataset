# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `count` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me a self-contained Elixir module `EtsCatalog` that implements **offset pagination over a concurrent, shared ETS-backed store**, with clamp-to-last-page semantics. This is the storage-and-listing core of a `GET /api/items` endpoint where many processes may be inserting items concurrently while pages are read. It must use ETS (not a database) so it stays self-contained and testable.

I need:

- `new()` — create and return a fresh ETS table handle backing the catalog. It must be an `:ordered_set` keyed by item id, and `:public` so that other processes can insert into it concurrently.

- `insert(table, item)` — insert a map that has at least an `:id` (integer) key, storing it under that id (later inserts with the same id overwrite). Returns `:ok`.

- `count(table)` — return the number of stored items.

- `list(table, params)` — offset pagination over a point-in-time snapshot of the table, ordered by id ascending. `params` is a map with optional string keys:
  - `"page"` — default `1`; `< 1` or non-numeric fall back to `1`.
  - `"page_size"` — default `20`; clamp to a maximum of `100`; `< 1` or non-numeric fall back to `20`.

  Returns `%{data: [...], meta: %{...}}` where `meta` contains:
  - `:requested_page` — the page the caller asked for (after coercion of bad values).
  - `:current_page` — the **effective** page actually served.
  - `:page_size`, `:total_count`, `:total_pages`.

The distinguishing behavior versus a plain paginator is **clamp-to-last-page**: when the requested page exceeds `total_pages`, do NOT return an empty list — clamp `current_page` down to `total_pages` and return that last page's items. When the catalog is empty, `current_page` is `1`, `total_pages` is `0`, and `data` is `[]`. `total_pages` is `ceil(total_count / page_size)`.

Because reads take a consistent snapshot (materialize and sort the current contents at call time), a `list/2` result is internally coherent even if concurrent inserts land during or after the call.

Use only the standard library (`:ets`). Give me the module in a single file.

## Additional interface contract

- `list/2`'s params argument is optional: `list(table)` must behave exactly like `list(table, %{})` (declare the second parameter with a `\\ %{}` default).

## The module with `count` missing

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

  def count(table) do
    # TODO
  end

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

Give me only the complete implementation of `count` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
