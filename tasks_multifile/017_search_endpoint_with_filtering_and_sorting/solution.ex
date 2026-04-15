<file path="priv/repo/migrations/20260402000000_create_products.exs">
defmodule MyApp.Repo.Migrations.CreateProducts do
  use Ecto.Migration

  def change do
    create table(:products) do
      add :name, :string, null: false
      add :category, :string, null: false
      add :price, :numeric, null: false

      timestamps()
    end

    create index(:products, [:category])
    create index(:products, [:price])
  end
end
</file>

<file path="lib/my_app/products/product.ex">
defmodule MyApp.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset

  schema "products" do
    field :name, :string
    field :category, :string
    field :price, :decimal

    timestamps()
  end

  @required_fields ~w(name category price)a

  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_number(:price, greater_than_or_equal_to: 0)
  end
end
</file>

<file path="lib/my_app/products.ex">
defmodule MyApp.Products do
  import Ecto.Query

  alias MyApp.Repo
  alias MyApp.Products.Product

  @allowed_sort_fields ~w(name price category)

  def list_products(params) when is_map(params) do
    case validate_sort(params) do
      {:error, _} = err ->
        err

      :ok ->
        products =
          Product
          |> filter_by_name(params)
          |> filter_by_category(params)
          |> filter_by_min_price(params)
          |> filter_by_max_price(params)
          |> apply_sorting(params)
          |> Repo.all()

        {:ok, products}
    end
  end

  defp validate_sort(%{"sort" => field}) when field not in @allowed_sort_fields do
    {:error, :invalid_sort_field}
  end

  defp validate_sort(_params), do: :ok

  defp filter_by_name(query, %{"name" => name}) when is_binary(name) and name != "" do
    wildcard = "%" <> name <> "%"
    where(query, [p], ilike(p.name, ^wildcard))
  end

  defp filter_by_name(query, _params), do: query

  defp filter_by_category(query, %{"category" => category})
       when is_binary(category) and category != "" do
    where(query, [p], p.category == ^category)
  end

  defp filter_by_category(query, _params), do: query

  defp filter_by_min_price(query, %{"min_price" => min}) when is_binary(min) and min != "" do
    case Decimal.parse(min) do
      {decimal, ""} -> where(query, [p], p.price >= ^decimal)
      _ -> query
    end
  end

  defp filter_by_min_price(query, _params), do: query

  defp filter_by_max_price(query, %{"max_price" => max}) when is_binary(max) and max != "" do
    case Decimal.parse(max) do
      {decimal, ""} -> where(query, [p], p.price <= ^decimal)
      _ -> query
    end
  end

  defp filter_by_max_price(query, _params), do: query

  defp apply_sorting(query, %{"sort" => field} = params) when field in @allowed_sort_fields do
    direction =
      case Map.get(params, "order", "asc") do
        "desc" -> :desc
        _ -> :asc
      end

    sort_atom = String.to_existing_atom(field)
    order_by(query, [p], [{^direction, field(p, ^sort_atom)}])
  end

  defp apply_sorting(query, _params), do: query
end
</file>

<file path="lib/my_app_web/controllers/product_controller.ex">
defmodule MyAppWeb.ProductController do
  use MyAppWeb, :controller

  alias MyApp.Products

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
</file>

<file path="lib/my_app_web/controllers/product_json.ex">
defmodule MyAppWeb.ProductJSON do
  alias MyApp.Products.Product

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
</file>

<file path="lib/my_app_web/router.ex">
# Add inside your existing :api scope:

scope "/api", MyAppWeb do
  pipe_through :api

  get "/products", ProductController, :index
end
</file>
