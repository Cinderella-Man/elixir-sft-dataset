# Implement the missing file

Below is the complete specification of a task, followed by its working,
fully tested multi-file solution — except that the entire content of
`lib/my_app/catalog/item.ex` has been blanked to `# TODO`. Write that file so the whole
bundle passes the task's full test suite again. Change nothing else —
every other file must stay exactly as shown.

## The task

Write me an Elixir Phoenix JSON API endpoint at `POST /api/items/bulk` that accepts a JSON array of items to create, validates each item independently, and reports per-item success or failure with position indices.

I need the following pieces:

**Schema & Validation (`MyApp.Catalog.Item`):**
- Fields: `name` (string, required, 1–255 chars), `price` (integer, required, must be > 0), `description` (string, optional, max 1000 chars).
- Standard Ecto schema with a `changeset/2` function enforcing those validations.
- Timestamps.

**Context module (`MyApp.Catalog`):**
- `bulk_create_items(list_of_attrs, opts \\ [])` — takes a list of attribute maps and an options keyword list.
- When `partial: true` is **not** in opts (the default), wrap everything in a single `Repo.transaction`. If any item fails validation, roll back the entire transaction and return `{:error, results}` where `results` is a list of `{index, :ok, item}` or `{index, :error, changeset}` tuples. No rows should be inserted.
- When `partial: true` is in opts, insert each valid item individually (still inside a transaction per item for safety) and skip invalid ones. Return `{:ok, results}` with the same tuple format. Valid items are persisted; invalid ones are not.
- In both modes every entry in the results list must include the zero-based position index from the original input so the caller knows exactly which items succeeded or failed.

**Controller (`MyAppWeb.BulkItemController`):**
- `create/2` action handling `POST /api/items/bulk`.
- Read the `partial` query param (`?partial=true`). Anything other than the literal string `"true"` means all-or-nothing mode.
- Request body shape: `{"items": [ {…}, {…}, … ]}`. If the `"items"` key is missing or is not a list, return 400 with `{"error": "expected a list of items"}`.
- On all-or-nothing success: respond 201 with `{"status": "all_created", "items": [...]}` where each entry has `"index"`, `"id"`, `"name"`, `"price"`, `"description"`.
- On all-or-nothing failure: respond 422 with `{"status": "all_failed", "errors": [...]}` where each failed entry has `"index"` and `"errors"` (a map of field → list of messages), and each successful validation still appears with `"index"` and `"valid": true` (but nothing was inserted).
- On partial mode: respond 201 with `{"status": "partial", "created": [...], "errors": [...]}`. `created` holds the successfully inserted items with their indices; `errors` holds the failures with indices and per-field error messages.

**Router:** Mount the route as `post "/api/items/bulk", BulkItemController, :create` inside an `/api` scope with the `:api` pipeline.

Give me the complete modules in separate files. Use only Phoenix, Ecto, and standard library — no external dependencies. Assume a Postgres repo at `MyApp.Repo` already exists and is configured.
## Additional interface contract

- Use exactly these module names: router `MyAppWeb.Router`, schema `MyApp.Catalog.Item`, repo `MyApp.Repo`. The repo itself is provided (already configured and started) by the test environment — do NOT define the repo module or a Phoenix endpoint. Your migration file will be run against it before the tests.
- The tests dispatch requests straight to `MyAppWeb.Router` with `Plug.Test` and parse the JSON request body with `Plug.Parsers` (no endpoint in front), so the route must be servable by the router pipeline alone.

## The bundle with `lib/my_app/catalog/item.ex` missing

```elixir
# TODO

defmodule MyApp.Catalog do
  @moduledoc """
  Catalog context. Bulk item creation with per-item, index-aware result reporting.
  """

  alias MyApp.Repo
  alias MyApp.Catalog.Item

  @doc """
  Bulk-create items from a list of attribute maps.

  Each entry in the returned `results` list is a 3-tuple carrying the zero-based
  position index from the original input: `{index, :ok, item}` or
  `{index, :error, changeset}`.

  Modes:
    * default (all-or-nothing) — wraps everything in a single `Repo.transaction`.
      If any item is invalid the whole transaction rolls back and
      `{:error, results}` is returned; no rows are inserted.
    * `partial: true` — inserts each valid item individually (each inside its own
      transaction) and skips invalid ones, returning `{:ok, results}`.
  """
  @spec bulk_create_items([map()], keyword()) ::
          {:ok, [{non_neg_integer(), :ok | :error, term()}]}
          | {:error, [{non_neg_integer(), :ok | :error, term()}]}
  def bulk_create_items(list_of_attrs, opts \\ []) do
    if Keyword.get(opts, :partial, false) do
      partial_create(list_of_attrs)
    else
      all_or_nothing(list_of_attrs)
    end
  end

  defp all_or_nothing(list_of_attrs) do
    Repo.transaction(fn ->
      results = insert_each(list_of_attrs)

      if Enum.any?(results, fn {_index, status, _} -> status == :error end) do
        Repo.rollback(results)
      else
        results
      end
    end)
  end

  defp partial_create(list_of_attrs) do
    results =
      list_of_attrs
      |> Enum.with_index()
      |> Enum.map(fn {attrs, index} ->
        outcome =
          Repo.transaction(fn ->
            case insert_item(attrs) do
              {:ok, item} -> item
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

        case outcome do
          {:ok, item} -> {index, :ok, item}
          {:error, changeset} -> {index, :error, changeset}
        end
      end)

    {:ok, results}
  end

  defp insert_each(list_of_attrs) do
    list_of_attrs
    |> Enum.with_index()
    |> Enum.map(fn {attrs, index} ->
      case insert_item(attrs) do
        {:ok, item} -> {index, :ok, item}
        {:error, changeset} -> {index, :error, changeset}
      end
    end)
  end

  defp insert_item(attrs) do
    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
  end
end

defmodule MyAppWeb.BulkItemController do
  use MyAppWeb, :controller

  alias MyApp.Catalog

  def create(conn, %{"items" => items}) when is_list(items) do
    conn = fetch_query_params(conn)

    if conn.query_params["partial"] == "true" do
      create_partial(conn, items)
    else
      create_all_or_nothing(conn, items)
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{"error" => "expected a list of items"})
  end

  defp create_all_or_nothing(conn, items) do
    case Catalog.bulk_create_items(items) do
      {:ok, results} ->
        conn
        |> put_status(201)
        |> json(%{"status" => "all_created", "items" => Enum.map(results, &item_json/1)})

      {:error, results} ->
        conn
        |> put_status(422)
        |> json(%{"status" => "all_failed", "errors" => Enum.map(results, &result_json/1)})
    end
  end

  defp create_partial(conn, items) do
    {:ok, results} = Catalog.bulk_create_items(items, partial: true)

    created = for {index, :ok, item} <- results, do: item_json({index, :ok, item})
    errors = for {index, :error, changeset} <- results, do: error_json(index, changeset)

    conn
    |> put_status(201)
    |> json(%{"status" => "partial", "created" => created, "errors" => errors})
  end

  # Successful validation but nothing inserted (all-or-nothing failure): mark valid.
  defp result_json({index, :ok, _item}), do: %{"index" => index, "valid" => true}
  defp result_json({index, :error, changeset}), do: error_json(index, changeset)

  defp item_json({index, :ok, item}) do
    %{
      "index" => index,
      "id" => item.id,
      "name" => item.name,
      "price" => item.price,
      "description" => item.description
    }
  end

  defp error_json(index, changeset) do
    %{"index" => index, "errors" => translate_errors(changeset)}
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r/%{(\w+)}/, msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end

defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", MyAppWeb do
    pipe_through(:api)

    post("/items/bulk", BulkItemController, :create)
  end
end

defmodule MyApp.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add(:name, :string, null: false)
      add(:price, :integer, null: false)
      add(:description, :text)

      timestamps()
    end
  end
end
```

Give me only the complete content of `lib/my_app/catalog/item.ex` — that one file, nothing
else.
