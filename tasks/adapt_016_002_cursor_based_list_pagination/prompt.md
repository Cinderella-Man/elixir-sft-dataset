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

Write me a self-contained Elixir module `CursorPaginator` that implements **cursor-based (keyset) pagination** — the pagination model used by large feeds and APIs where offset pagination is too expensive and unstable. This is the pagination core of a `GET /api/items` list endpoint, but implemented as a pure function over an in-memory list so it can be tested without a database.

I need the following:

- A function `paginate(items, params)` where `items` is a list of maps, each having at least an `:id` (integer) key, and `params` is a map with optional string keys as they would arrive from query params:
  - `"limit"` — page size. Default `20`. Clamp to a maximum of `100`. Values `< 1`, non-numeric, or not *fully* numeric (a value like `"12abc"` with trailing junk is rejected, not read as `12`) fall back to the default.
  - `"cursor"` — an **opaque** cursor string (see below). A missing cursor means start from the beginning. A malformed/undecodable cursor is treated gracefully as no cursor (start from the beginning) — it must NOT raise or return an error.
  - `"direction"` — `"next"` (default) or `"prev"`.

- Items are always ordered by `:id` ascending, regardless of the order of the input list.

- The result is a map `%{data: [...], meta: %{...}}` where `meta` contains exactly these five keys and no others (in particular, no `:total_count` or `:total_pages`):
  - `:page_size` — the effective limit.
  - `:next_cursor` — an opaque cursor pointing after the last returned item, or `nil` when there is nothing after the window.
  - `:prev_cursor` — an opaque cursor pointing before the first returned item, or `nil` when there is nothing before the window.
  - `:has_next` — boolean, whether items exist after the returned window.
  - `:has_prev` — boolean, whether items exist before the returned window.

- Forward paging (`"next"`) with cursor `c` returns the items with `id > c` (the first `limit` of them). Backward paging (`"prev"`) with cursor `c` returns the items with `id < c` — the LAST `limit` of them — still returned in ascending `:id` order.

- Unlike offset pagination there is **no** `total_count` or `total_pages`; correctness comes from the cursor boundary, so inserting/deleting rows between requests never skips or duplicates rows within a stable id ordering.

- Expose `encode_cursor(id)` and `decode_cursor(cursor)` as public helpers. The cursor must be opaque and URL-safe: it must contain only characters matching `[A-Za-z0-9_-]` (e.g. **unpadded** base64url of an internal representation — no `=` padding), must round-trip for any integer id (including `0`, negatives, and very large values), and must not embed the raw id as a literal substring. `decode_cursor/1` returns `{:ok, id}` for a valid cursor or `:error` for anything malformed; non-binary input (e.g. an integer) also returns `:error` rather than raising.

When `data` is empty, both cursors are `nil` and both booleans are `false`.

Use only the standard library. Give me the module in a single file.

## Additional interface contract

- `paginate/2`'s params argument is optional: `paginate(items)` must behave exactly like `paginate(items, %{})` (declare the second parameter with a `\\ %{}` default).
