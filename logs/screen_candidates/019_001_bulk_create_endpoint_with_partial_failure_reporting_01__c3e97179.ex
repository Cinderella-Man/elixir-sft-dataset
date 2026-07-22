<file path="lib/my_app/catalog.ex">
defmodule MyApp.Catalog do
  @moduledoc """
  The Catalog context.

  Exposes bulk creation of `MyApp.Catalog.Item` records with two distinct semantics:

    * **all-or-nothing** (the default) — every item is validated and inserted inside a single
      transaction; a single failure rolls the whole transaction back and nothing is persisted;
    * **partial** (`partial: true`) — each valid item is inserted on its own; invalid items are
      simply skipped and reported back to the caller.

  In both modes the returned results carry the zero-based position index of each item in the
  original input list, so the caller can always tell exactly which items succeeded or failed.
  """

  alias Ecto.Changeset
  alias MyApp.Catalog.Item
  alias MyApp.Repo

  @typedoc "A per-item outcome carrying the zero-based index of the item in the input list."
  @type result ::
          {non_neg_integer(), :ok, Item.t()}
          | {non_neg_integer(), :error, Changeset.t(Item.t())}

  @doc """
  Creates many items at once, reporting the outcome of each one by position.

  `list_of_attrs` is a list of attribute maps (string- or atom-keyed). Each entry is validated
  independently through `MyApp.Catalog.Item.changeset/2`.

  ## Options

    * `:partial` — when `true`, valid items are inserted and invalid ones are skipped; the
      function then always returns `{:ok, results}`. Defaults to `false`, in which case a
      single invalid item rolls back the whole transaction and `{:error, results}` is
      returned with nothing inserted.

  ## Return value

  `results` is a list of `{index, :ok, item}` / `{index, :error, changeset}` tuples ordered by
  the zero-based `index` of the item in `list_of_attrs`.

  ## Examples

      iex> MyApp.Catalog.bulk_create_items([%{"name" => "Cup", "price" => 5}])
      {:ok, [{0, :ok, %MyApp.Catalog.Item{}}]}

  """
  @spec bulk_create_items([map()], keyword()) :: {:ok, [result()]} | {:error, [result()]}
  def bulk_create_items(list_of_attrs, opts \\ []) when is_list(list_of_attrs) and is_list(opts) do
    if Keyword.get(opts, :partial, false) == true do
      partial_create(list_of_attrs)
    else
      all_or_nothing_create(list_of_attrs)
    end
  end

  @spec all_or_nothing_create([map()]) :: {:ok, [result()]} | {:error, [result()]}
  defp all_or_nothing_create(list_of_attrs) do
    Repo.transaction(fn ->
      results =
        list_of_attrs
        |> Enum.with_index()
        |> Enum.map(fn {attrs, index} -> insert_one(attrs, index) end)

      if Enum.any?(results, &error_result?/1) do
        Repo.rollback(results)
      else
        results
      end
    end)
  end

  @spec partial_create([map()]) :: {:ok, [result()]}
  defp partial_create(list_of_attrs) do
    results =
      list_of_attrs
      |> Enum.with_index()
      |> Enum.map(fn {attrs, index} ->
        case Repo.transaction(fn -> insert_one(attrs, index) end) do
          {:ok, result} -> result
          {:error, result} -> result
        end
      end)

    {:ok, results}
  end

  @spec insert_one(map(), non_neg_integer()) :: result()
  defp insert_one(attrs, index) do
    case attrs |> build_changeset() |> Repo.insert() do
      {:ok, item} -> {index, :ok, item}
      {:error, changeset} -> {index, :error, changeset}
    end
  end

  @spec build_changeset(term()) :: Changeset.t(Item.t())
  defp build_changeset(attrs) when is_map(attrs) do
    Item.changeset(%Item{}, attrs)
  end

  defp build_changeset(_attrs) do
    %Item{}
    |> Item.changeset(%{})
    |> Changeset.add_error(:base, "is invalid, expected an object")
  end

  @spec error_result?(result()) :: boolean()
  defp error_result?({_index, :error, _changeset}), do: true
  defp error_result?({_index, :ok, _item}), do: false
end
</file>
<file path="lib/my_app/catalog/item.ex">
defmodule MyApp.Catalog.Item do
  @moduledoc """
  Ecto schema for a catalog item.

  An item has a required `name` (1–255 characters), a required `price` (a positive integer,
  expressed in the smallest currency unit) and an optional `description` (at most 1000
  characters).

  Validation lives entirely in `changeset/2` so that callers — most notably
  `MyApp.Catalog.bulk_create_items/2` — can validate many items independently without
  touching the database.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          price: integer() | nil,
          description: String.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @castable_fields [:name, :price, :description]

  schema "items" do
    field :name, :string
    field :price, :integer
    field :description, :string

    timestamps()
  end

  @doc """
  Builds a changeset for an item.

  Enforces the item invariants:

    * `:name` — required, between 1 and 255 characters;
    * `:price` — required, strictly greater than zero;
    * `:description` — optional, at most 1000 characters.

  ## Examples

      iex> MyApp.Catalog.Item.changeset(%MyApp.Catalog.Item{}, %{"name" => "Cup", "price" => 5}).valid?
      true

      iex> MyApp.Catalog.Item.changeset(%MyApp.Catalog.Item{}, %{"name" => "Cup", "price" => 0}).valid?
      false

  """
  @spec changeset(t() | Ecto.Changeset.t(t()), map()) :: Ecto.Changeset.t(t())
  def changeset(item, attrs) do
    item
    |> cast(attrs, @castable_fields)
    |> validate_required([:name, :price])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_number(:price, greater_than: 0)
    |> validate_length(:description, max: 1000)
  end
end
</file>
<file path="lib/my_app_web/controllers/bulk_item_controller.ex">
defmodule MyAppWeb.BulkItemController do
  @moduledoc """
  JSON API controller for bulk item creation.

  Serves `POST /api/items/bulk`, expecting a body shaped as `{"items": [ {...}, ... ]}`.

  The `?partial=true` query parameter switches the endpoint from the default all-or-nothing
  mode (a single invalid item rolls back every insert) to partial mode (valid items are
  persisted, invalid ones are reported but skipped). Any other value — including an absent
  parameter — means all-or-nothing.

  Every response entry carries the zero-based `index` of the item in the submitted list.
  """

  use Phoenix.Controller

  import Plug.Conn

  alias Ecto.Changeset
  alias MyApp.Catalog
  alias MyApp.Catalog.Item

  @doc """
  Creates a batch of items.

  Responds with:

    * `400` and `{"error": "expected a list of items"}` when `"items"` is missing or not a list;
    * `201` and `{"status": "all_created", "items": [...]}` when every item was inserted;
    * `422` and `{"status": "all_failed", "errors": [...]}` when at least one item was invalid
      in all-or-nothing mode (nothing is inserted; valid items are echoed as
      `{"index" => i, "valid" => true}`);
    * `201` and `{"status": "partial", "created": [...], "errors": [...]}` in partial mode.

  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, params) do
    conn = fetch_query_params(conn)
    partial? = Map.get(conn.query_params, "partial") == "true"

    case Map.get(params, "items") do
      items when is_list(items) -> dispatch(conn, items, partial?)
      _other -> bad_request(conn)
    end
  end

  @spec dispatch(Plug.Conn.t(), [map()], boolean()) :: Plug.Conn.t()
  defp dispatch(conn, items, true) do
    {:ok, results} = Catalog.bulk_create_items(items, partial: true)

    payload = %{
      "status" => "partial",
      "created" => results |> Enum.filter(&ok_result?/1) |> Enum.map(&render_item/1),
      "errors" => results |> Enum.reject(&ok_result?/1) |> Enum.map(&render_error/1)
    }

    conn |> put_status(:created) |> json(payload)
  end

  defp dispatch(conn, items, false) do
    case Catalog.bulk_create_items(items) do
      {:ok, results} ->
        payload = %{"status" => "all_created", "items" => Enum.map(results, &render_item/1)}
        conn |> put_status(:created) |> json(payload)

      {:error, results} ->
        payload = %{"status" => "all_failed", "errors" => Enum.map(results, &render_outcome/1)}
        conn |> put_status(:unprocessable_entity) |> json(payload)
    end
  end

  @spec bad_request(Plug.Conn.t()) :: Plug.Conn.t()
  defp bad_request(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{"error" => "expected a list of items"})
  end

  @spec ok_result?(Catalog.result()) :: boolean()
  defp ok_result?({_index, :ok, _item}), do: true
  defp ok_result?({_index, :error, _changeset}), do: false

  @spec render_item(Catalog.result()) :: map()
  defp render_item({index, :ok, %Item{} = item}) do
    %{
      "index" => index,
      "id" => item.id,
      "name" => item.name,
      "price" => item.price,
      "description" => item.description
    }
  end

  @spec render_error(Catalog.result()) :: map()
  defp render_error({index, :error, changeset}) do
    %{"index" => index, "errors" => translate_errors(changeset)}
  end

  @spec render_outcome(Catalog.result()) :: map()
  defp render_outcome({index, :ok, _item}), do: %{"index" => index, "valid" => true}
  defp render_outcome({_index, :error, _changeset} = result), do: render_error(result)

  @spec translate_errors(Changeset.t()) :: map()
  defp translate_errors(changeset) do
    Changeset.traverse_errors(changeset, &translate_error/1)
  end

  @spec translate_error({String.t(), keyword()}) :: String.t()
  defp translate_error({msg, opts}) do
    Regex.replace(~r"%{(\w+)}", msg, fn _whole, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
</file>
<file path="lib/my_app_web/router.ex">
defmodule MyAppWeb.Router do
  @moduledoc """
  Application router.

  Exposes the JSON API under `/api`, including `POST /api/items/bulk`, which is handled by
  `MyAppWeb.BulkItemController.create/2`.

  The `:api` pipeline only negotiates the JSON format, so the router is fully servable on its
  own (for example when requests are dispatched directly with `Plug.Test`, with `Plug.Parsers`
  in front of it and no `Phoenix.Endpoint`).
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MyAppWeb do
    pipe_through :api

    post "/items/bulk", BulkItemController, :create
  end
end
</file>
<file path="priv/repo/migrations/20240101000000_create_items.exs">
defmodule MyApp.Repo.Migrations.CreateItems do
  @moduledoc """
  Creates the `items` table backing `MyApp.Catalog.Item`.

  `name` and `price` are NOT NULL, mirroring the required-field validations in the schema's
  changeset; `description` is nullable.
  """

  use Ecto.Migration

  @doc """
  Creates the `items` table with its timestamps.
  """
  @spec change() :: term()
  def change do
    create table(:items) do
      add :name, :string, size: 255, null: false
      add :price, :integer, null: false
      add :description, :string, size: 1000

      timestamps()
    end
  end
end
</file>