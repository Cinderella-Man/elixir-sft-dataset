<file path="lib/my_app/products.ex">
defmodule MyApp.Products do
  @moduledoc """
  The Products context.

  Builds a single composable Ecto query for listing products with optional
  case-insensitive name search, exact category filtering, inclusive price
  bounds, and an allowlisted sort field/direction. All filtering and sorting
  is performed at the database level in one round-trip.
  """

  import Ecto.Query, warn: false

  alias MyApp.Products.Product
  alias MyApp.Repo

  @allowed_sort_fields ~w(name price category)

  @doc """
  Lists products matching the given string-keyed `params` map.

  Supported params: `"name"` (partial, case-insensitive `ILIKE`), `"category"`
  (exact match), `"min_price"`/`"max_price"` (inclusive bounds), `"sort"` (one
  of `"name"`, `"price"`, `"category"`) and `"order"` (`"asc"`/`"desc"`,
  defaulting to `"asc"`).

  Returns `{:ok, products}` on success, or `{:error, :invalid_sort}` when a
  `"sort"` value outside the allowlist is supplied.
  """
  @spec list_products(map()) :: {:ok, [Product.t()]} | {:error, :invalid_sort}
  def list_products(params) do
    case validate_sort(params) do
      :ok ->
        query =
          Product
          |> filter_by_name(params)
          |> filter_by_category(params)
          |> filter_by_min_price(params)
          |> filter_by_max_price(params)
          |> sort_products(params)

        {:ok, Repo.all(query)}

      {:error, :invalid_sort} = error ->
        error
    end
  end

  @spec validate_sort(map()) :: :ok | {:error, :invalid_sort}
  defp validate_sort(%{"sort" => sort}) when sort in @allowed_sort_fields, do: :ok
  defp validate_sort(%{"sort" => sort}) when is_binary(sort), do: {:error, :invalid_sort}
  defp validate_sort(_params), do: :ok

  @spec filter_by_name(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp filter_by_name(query, %{"name" => name}) when is_binary(name) and name != "" do
    pattern = "%#{name}%"
    from p in query, where: ilike(p.name, ^pattern)
  end

  defp filter_by_name(query, _params), do: query

  @spec filter_by_category(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp filter_by_category(query, %{"category" => category})
       when is_binary(category) and category != "" do
    from p in query, where: p.category == ^category
  end

  defp filter_by_category(query, _params), do: query

  @spec filter_by_min_price(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp filter_by_min_price(query, %{"min_price" => value})
       when is_binary(value) and value != "" do
    case Decimal.parse(value) do
      {decimal, _rest} -> from p in query, where: p.price >= ^decimal
      :error -> query
    end
  end

  defp filter_by_min_price(query, _params), do: query

  @spec filter_by_max_price(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp filter_by_max_price(query, %{"max_price" => value})
       when is_binary(value) and value != "" do
    case Decimal.parse(value) do
      {decimal, _rest} -> from p in query, where: p.price <= ^decimal
      :error -> query
    end
  end

  defp filter_by_max_price(query, _params), do: query

  @spec sort_products(Ecto.Queryable.t(), map()) :: Ecto.Queryable.t()
  defp sort_products(query, %{"sort" => sort} = params)
       when sort in @allowed_sort_fields do
    field = String.to_existing_atom(sort)
    direction = sort_direction(params)
    from p in query, order_by: [{^direction, ^field}]
  end

  defp sort_products(query, _params), do: query

  @spec sort_direction(map()) :: :asc | :desc
  defp sort_direction(%{"order" => "desc"}), do: :desc
  defp sort_direction(_params), do: :asc
end
</file>
<file path="lib/my_app/products/product.ex">
defmodule MyApp.Products.Product do
  @moduledoc """
  Ecto schema for a product.

  A product has a human-readable `name`, a `category` used for exact-match
  filtering, and a `price` stored as an arbitrary-precision decimal so that
  monetary values keep their exact representation.
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
  Builds a changeset casting and validating `:name`, `:category` and `:price`.

  All three fields are required. `attrs` is expected to be a map keyed by the
  atoms `:name`, `:category` and `:price` (string keys are also accepted).
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
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
  JSON controller exposing `GET /api/products`.

  Delegates query building to `MyApp.Products` and renders results through
  `MyAppWeb.ProductJSON`. Returns HTTP 400 with `{"error": "invalid sort
  field"}` when an unsupported sort field is requested.
  """

  use Phoenix.Controller

  alias MyApp.Products

  @doc """
  Handles the products index request, applying search/filter/sort `params`.
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, params) do
    case Products.list_products(params) do
      {:ok, products} ->
        conn
        |> put_status(:ok)
        |> put_view(json: MyAppWeb.ProductJSON)
        |> render(:index, products: products)

      {:error, :invalid_sort} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid sort field"})
    end
  end
end
</file>
<file path="lib/my_app_web/controllers/product_json.ex">
defmodule MyAppWeb.ProductJSON do
  @moduledoc """
  JSON serialization for products.

  Prices are serialized as strings to preserve exact decimal precision.
  """

  alias MyApp.Products.Product

  @doc """
  Renders a list of products as `%{data: [...]}`.
  """
  @spec index(%{products: [Product.t()]}) :: %{data: [map()]}
  def index(%{products: products}) do
    %{data: Enum.map(products, &data/1)}
  end

  @doc """
  Renders a single product as a plain map with its price as a string.
  """
  @spec data(Product.t()) :: map()
  def data(%Product{} = product) do
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
  `MyAppWeb.ProductController`.
  """

  use Phoenix.Router

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
  Creates the `products` table with name, category, decimal price and
  standard timestamps.
  """

  use Ecto.Migration

  @doc """
  Creates the `products` table.
  """
  @spec change() :: any()
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