<file path="lib/my_app/products.ex">
defmodule MyApp.Products do
  @moduledoc """
  The Products context.

  Builds and runs a single composable Ecto query for listing products with
  optional case-insensitive name search, exact category filtering, inclusive
  price bounds, and allowlisted sorting. All filtering and ordering happens at
  the database level in one round-trip.
  """

  import Ecto.Query, warn: false

  alias MyApp.Products.Product
  alias MyApp.Repo

  @sort_fields ~w(name price category)

  @doc """
  Lists products, applying every supported filter and sort present in `params`.

  Recognised string keys: `"name"` (partial, case-insensitive `ILIKE`),
  `"category"` (exact match), `"min_price"`/`"max_price"` (inclusive bounds),
  `"sort"` (one of `name`, `price`, `category`), and `"order"` (`asc`/`desc`,
  defaulting to `asc`). Unknown or blank values are ignored. An unrecognised
  sort field is silently dropped here; callers should reject it beforehand.
  """
  @spec list_products(map()) :: [Product.t()]
  def list_products(params) do
    Product
    |> filter_name(params)
    |> filter_category(params)
    |> filter_min_price(params)
    |> filter_max_price(params)
    |> sort_products(params)
    |> Repo.all()
  end

  defp filter_name(query, %{"name" => name}) when is_binary(name) and name != "" do
    pattern = "%#{name}%"
    from p in query, where: ilike(p.name, ^pattern)
  end

  defp filter_name(query, _params), do: query

  defp filter_category(query, %{"category" => category})
       when is_binary(category) and category != "" do
    from p in query, where: p.category == ^category
  end

  defp filter_category(query, _params), do: query

  defp filter_min_price(query, %{"min_price" => value}) do
    case parse_decimal(value) do
      {:ok, decimal} -> from p in query, where: p.price >= ^decimal
      :error -> query
    end
  end

  defp filter_min_price(query, _params), do: query

  defp filter_max_price(query, %{"max_price" => value}) do
    case parse_decimal(value) do
      {:ok, decimal} -> from p in query, where: p.price <= ^decimal
      :error -> query
    end
  end

  defp filter_max_price(query, _params), do: query

  defp sort_products(query, %{"sort" => sort} = params) when sort in @sort_fields do
    field = String.to_existing_atom(sort)
    direction = sort_direction(params)
    from p in query, order_by: [{^direction, ^field}]
  end

  defp sort_products(query, _params), do: query

  defp sort_direction(%{"order" => "desc"}), do: :desc
  defp sort_direction(_params), do: :asc

  defp parse_decimal(%Decimal{} = value), do: {:ok, value}
  defp parse_decimal(value) when is_integer(value), do: {:ok, Decimal.new(value)}

  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} -> {:ok, decimal}
      _other -> :error
    end
  end

  defp parse_decimal(_value), do: :error
end
</file>
<file path="lib/my_app/products/product.ex">
defmodule MyApp.Products.Product do
  @moduledoc """
  Ecto schema for a product.

  A product has a `name`, a `category`, and a `price`. The price is stored as a
  PostgreSQL `numeric`/`decimal` column and represented in Elixir as a
  `Decimal` struct so that monetary precision is never lost to float rounding.
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
    field :name, :string
    field :category, :string
    field :price, :decimal

    timestamps()
  end

  @doc """
  Builds a changeset for a product from the given attributes.

  Casts and requires `:name`, `:category`, and `:price`. Accepts an attribute
  map keyed by those atoms, matching how test fixtures are inserted.
  """
  @spec changeset(t() | Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(product, attrs) do
    product
    |> cast(attrs, [:name, :category, :price])
    |> validate_required([:name, :category, :price])
  end
end
</file>
<file path="lib/my_app_web/controllers/product_controller.ex">
defmodule MyAppWeb.ProductController do
  @moduledoc """
  Controller for the products JSON API.

  Exposes `index/2`, which validates the optional `sort` parameter against an
  allowlist, delegates query building to `MyApp.Products`, and renders results
  through `MyAppWeb.ProductJSON`. An invalid sort field yields HTTP 400.
  """

  use Phoenix.Controller, formats: [:json]

  alias MyApp.Products
  alias MyAppWeb.ProductJSON

  plug :put_view, json: ProductJSON

  @valid_sorts ~w(name price category)

  @doc """
  Handles `GET /api/products`.

  When a `sort` parameter is present it must be one of `name`, `price`, or
  `category`; otherwise the response is HTTP 400 with body
  `{"error": "invalid sort field"}`. Otherwise responds HTTP 200 with the
  matching products under a `"data"` key.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    if valid_sort?(params) do
      products = Products.list_products(params)
      render(conn, :index, products: products)
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "invalid sort field"})
    end
  end

  defp valid_sort?(%{"sort" => sort}), do: sort in @valid_sorts
  defp valid_sort?(_params), do: true
end
</file>
<file path="lib/my_app_web/controllers/product_json.ex">
defmodule MyAppWeb.ProductJSON do
  @moduledoc """
  JSON view for products.

  Renders a list of `%MyApp.Products.Product{}` structs into the API response
  shape `%{data: [...]}`, serialising `price` as a string to preserve decimal
  precision.
  """

  alias MyApp.Products.Product

  @doc """
  Renders the `index` template as a map with a `:data` list of products.
  """
  @spec index(%{products: [Product.t()]}) :: %{data: [map()]}
  def index(%{products: products}) do
    %{data: Enum.map(products, &data/1)}
  end

  defp data(%Product{} = product) do
    %{
      id: product.id,
      name: product.name,
      category: product.category,
      price: Decimal.to_string(product.price)
    }
  end
end
</file>
<file path="lib/my_app_web/router.ex">
defmodule MyAppWeb.Router do
  @moduledoc """
  Application router.

  Defines the `:api` pipeline and routes `GET /api/products` to
  `MyAppWeb.ProductController.index/2`.
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MyAppWeb do
    pipe_through :api

    get "/products", ProductController, :index
  end
end
</file>
<file path="priv/repo/migrations/20260723000000_create_products.exs">
defmodule MyApp.Repo.Migrations.CreateProducts do
  @moduledoc """
  Creates the `products` table with `name`, `category`, a decimal `price`, and
  standard `inserted_at`/`updated_at` timestamps.
  """

  use Ecto.Migration

  @doc """
  Creates the `products` table.
  """
  @spec change() :: term()
  def change do
    create table(:products) do
      add :name, :string, null: false
      add :category, :string, null: false
      add :price, :decimal, null: false

      timestamps()
    end
  end
end
</file>