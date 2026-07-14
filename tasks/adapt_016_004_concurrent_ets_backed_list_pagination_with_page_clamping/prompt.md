# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
<file path="lib/paginated_list/item.ex">
defmodule PaginatedList.Item do
  use Ecto.Schema
  import Ecto.Changeset

  schema "items" do
    field(:name, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:name])
    |> validate_required([:name])
  end
end
</file>

<file path="priv/repo/migrations/20240101000000_create_items.exs">
defmodule PaginatedList.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add(:name, :string, null: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:items, [:inserted_at, :id]))
  end
end
</file>

<file path="lib/paginated_list/items.ex">
defmodule PaginatedList.Items do
  @moduledoc """
  Context for managing Items with offset pagination.
  """

  import Ecto.Query, warn: false

  alias PaginatedList.Item
  alias PaginatedList.Repo

  @default_page 1
  @default_page_size 20
  @max_page_size 100

  @spec list_items(map()) :: %{
          data: [Item.t()],
          meta: %{
            current_page: pos_integer(),
            page_size: pos_integer(),
            total_count: non_neg_integer(),
            total_pages: non_neg_integer()
          }
        }
  def list_items(params \\ %{}) do
    page = parse_page(params)
    page_size = parse_page_size(params)
    offset = (page - 1) * page_size

    base_query = from(i in Item, order_by: [asc: i.inserted_at, asc: i.id])

    total_count = Repo.aggregate(base_query, :count, :id)
    total_pages = compute_total_pages(total_count, page_size)

    items =
      base_query
      |> limit(^page_size)
      |> offset(^offset)
      |> Repo.all()

    %{
      data: items,
      meta: %{
        current_page: page,
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

  defp parse_page(_params), do: @default_page

  defp parse_page_size(%{"page_size" => raw}) do
    case Integer.parse(to_string(raw)) do
      {n, _} when n >= 1 -> min(n, @max_page_size)
      _ -> @default_page_size
    end
  end

  defp parse_page_size(_params), do: @default_page_size

  defp compute_total_pages(0, _page_size), do: 0
  defp compute_total_pages(total_count, page_size), do: ceil(total_count / page_size)
end
</file>

<file path="lib/paginated_list_web/controllers/item_controller.ex">
defmodule PaginatedListWeb.ItemController do
  use PaginatedListWeb, :controller

  alias PaginatedList.Items

  def index(conn, params) do
    %{data: items, meta: meta} = Items.list_items(params)

    json(conn, %{
      data: Enum.map(items, &serialize_item/1),
      meta: %{
        current_page: meta.current_page,
        page_size: meta.page_size,
        total_count: meta.total_count,
        total_pages: meta.total_pages
      }
    })
  end

  defp serialize_item(item) do
    %{
      id: item.id,
      name: item.name,
      inserted_at: DateTime.to_iso8601(item.inserted_at)
    }
  end
end
</file>

<file path="lib/paginated_list_web/router.ex">
defmodule PaginatedListWeb.Router do
  use PaginatedListWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", PaginatedListWeb do
    pipe_through(:api)

    get("/items", ItemController, :index)
  end
end
</file>
```

## New specification

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
