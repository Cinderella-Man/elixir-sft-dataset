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