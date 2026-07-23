# Implement the missing file

Below: the task, then its tested multi-file solution in which the whole
of `lib/my_app/products.ex` has been blanked to `# TODO`. Reconstruct that single file;
the remaining files are fixed and must stay exactly as shown.

## The task

Write me a Phoenix JSON API endpoint `GET /api/products` that supports searching, filtering, and sorting against a `products` table backed by Ecto and PostgreSQL.

## Schema and Migration

Create an Ecto schema `MyApp.Products.Product` with at least these fields:

- `name` — `:string`, required
- `category` — `:string`, required
- `price` — `:decimal`, required (stored as a numeric/decimal type, not float)

Also create the corresponding migration that creates the `products` table with those columns plus standard `inserted_at` / `updated_at` timestamps.

## Query Parameters

The endpoint must accept the following optional query parameters and apply them all together when multiple are present:

- **`name`** — partial, case-insensitive search on the product name. `?name=shoe` should match "Running Shoes", "SHOE rack", "snowshoe", etc. Use `ILIKE` with wildcards on both sides.

- **`category`** — exact match filter on the category field. `?category=electronics` matches only products whose category is literally `"electronics"`.

- **`min_price`** — inclusive lower bound on price. `?min_price=10` means `price >= 10`.

- **`max_price`** — inclusive upper bound on price. `?max_price=50` means `price <= 50`.

- **`sort`** — the field to sort by. Only the values `"name"`, `"price"`, and `"category"` are allowed. Any other value must cause the endpoint to return HTTP 400 with a JSON body `{"error": "invalid sort field"}`.

- **`order`** — sort direction, either `"asc"` or `"desc"`. Defaults to `"asc"` if `sort` is provided but `order` is not. If `order` is provided without `sort`, ignore it.

If no query parameters are provided, return all products with no particular ordering guarantee.

## Response Format

Always respond with HTTP 200 (except for the 400 case above) and a JSON body:

```json
{"data": [{"id": 1, "name": "Widget", "category": "gadgets", "price": "19.99"}, ...]}
```

Price should be serialized as a string to preserve decimal precision. An empty result set returns `{"data": []}` with status 200.

## Security

The sort field validation must act as an allowlist. Never interpolate user input directly into the query as a column name — convert the validated string to an existing atom and use that with Ecto's `order_by`. This prevents SQL injection through the sort parameter.

## Architecture

- Put the query-building logic in a context module `MyApp.Products` with a function like `list_products(params)` that accepts the params map and returns a list of `%Product{}` structs. Build the Ecto query by starting with `Product` and piping through conditional filter functions.
- The controller `MyAppWeb.ProductController` should have an `index/2` action that delegates to the context module and renders the result through a `MyAppWeb.ProductJSON` view module.
- Wire the route in the existing `:api` pipeline in the router.

## Constraints

- Use only Ecto and Phoenix (no external search libraries).
- The query must be a single composable Ecto query — no multiple round-trips to the database.
- All filtering and sorting happens at the database level, not in Elixir.

Give me all the files: migration, schema, context, controller, JSON view, and router addition. Each in its own code block with the file path as a comment at the top.
## Additional interface contract

- Use exactly these module names: router `MyAppWeb.Router`, repo `MyApp.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `MyAppWeb.Router` with `Plug.Test` (no endpoint in front), so `GET /api/products` must be servable by the router pipeline alone.
- Test fixtures are inserted as `%Product{} |> Product.changeset(attrs) |> MyApp.Repo.insert!()` with `attrs` a map of `:name`, `:category`, `:price` — `Product.changeset/2` must accept exactly that shape.

## The bundle with `lib/my_app/products.ex` missing

```elixir
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add(:name, :string, null: false)
      add(:category, :string, null: false)
      add(:price, :numeric, null: false)

      timestamps()
    end

    create(index(:products, [:category]))
    create(index(:products, [:price]))
  end
end

defmodule MyApp.Products.Product do
  @moduledoc """
  Ecto schema for a catalog product: a `name`, a `category`, and a non-negative
  `price`, plus insertion/update timestamps.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          category: String.t() | nil,
          price: Decimal.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "products" do
    field(:name, :string)
    field(:category, :string)
    field(:price, :decimal)

    timestamps()
  end

  @required_fields ~w(name category price)a

  @doc """
  Builds a changeset casting `name`, `category`, and `price`, requiring all three
  and enforcing a non-negative price.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end

# TODO

defmodule MyAppWeb.ProductController do
  @moduledoc """
  JSON endpoint for listing products. Delegates filtering/sorting to the
  `MyApp.Products` context and renders via `MyAppWeb.ProductJSON`.
  """

  use MyAppWeb, :controller

  alias MyApp.Products

  @doc "GET /api/products — renders the filtered list, or 400 on an invalid sort field."
  def index(conn, params) do
    case Products.list_products(params) do
      {:ok, products} ->
        conn
        |> put_status(:ok)
        |> json(MyAppWeb.ProductJSON.index(%{products: products}))

      {:error, :invalid_sort_field} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid sort field"})
    end
  end
end

defmodule MyAppWeb.ProductJSON do
  @moduledoc "Serializes products into the `%{data: [...]}` JSON response shape."

  alias MyApp.Products.Product

  @doc "Renders the product list as `%{data: [product_map]}`."
  def index(%{products: products}) do
    %{data: Enum.map(products, &product/1)}
  end

  defp product(%Product{} = p) do
    %{
      id: p.id,
      name: p.name,
      category: p.category,
      price: Decimal.to_string(p.price)
    }
  end
end

defmodule MyAppWeb.Router do
  @moduledoc false
  use MyAppWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", MyAppWeb do
    pipe_through(:api)

    get("/products", ProductController, :index)
  end
end
```

Output only `lib/my_app/products.ex`'s full content — one file, nothing besides.
