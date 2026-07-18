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

Write me a self-contained Elixir module `QueryPaginator` that implements **offset pagination with multi-field sorting, filtering, and strict validation**. This is the query core of a `GET /api/items` list endpoint, implemented as a pure function over an in-memory list so it can be tested without a database. Unlike a plain paginator, this one validates its inputs and returns tagged error tuples on bad requests instead of silently coercing them.

Each item is a map with `:id` (integer), `:name` (string), and `:age` (integer).

I need `paginate(items, params)` returning `{:ok, %{data: [...], meta: %{...}}}` or `{:error, reason}`, where `params` is a map with optional string keys:

- `"page"` — default `1`; values `< 1` or non-numeric fall back to `1`.
- `"page_size"` — default `20`; clamp to a maximum of `100`; values `< 1` or non-numeric fall back to `20`.
- `"sort"` — the field to sort by. Allowed fields are exactly `"id"`, `"name"`, `"age"`. Any other value returns `{:error, :invalid_sort_field}`. Default `:id`.
- `"order"` — `"asc"` (default) or `"desc"`. Any other value returns `{:error, :invalid_order}`.
- `"min_age"` / `"max_age"` — optional integer filters, each an inclusive bound on `:age` (an item passes when `age >= min_age` and `age <= max_age`). A present-but-non-integer value returns `{:error, :invalid_filter}`.
- `"name_contains"` — optional case-insensitive substring filter on `:name`.

Validation happens before any work: if any of sort/order/filters are invalid, return the corresponding `{:error, reason}` and do NOT return partial data.

On success:
- Sorting is deterministic: sort by the chosen field, using `:id` ascending as the tiebreak; `"desc"` reverses the ordering. String fields sort by default term (codepoint) order, so uppercase names sort before lowercase ones.
- `total_count` is the count AFTER filtering. `total_pages` is `ceil(total_count / page_size)`, or `0` when there are zero matching items.
- `meta` includes `:current_page`, `:page_size`, `:total_count`, `:total_pages`, `:sort` (atom), `:order` (atom), and `:filters` (a map with `:min_age`, `:max_age`, `:name_contains`, each `nil` when unset).
- Requesting a page beyond `total_pages` returns an empty `data` list but still-correct metadata (mirror the base endpoint's behavior here).

Use only the standard library. Give me the module in a single file.

## Additional interface contract

- `paginate/2`'s params argument is optional: `paginate(items)` must behave exactly like `paginate(items, %{})` (declare the second parameter with a `\\ %{}` default).
