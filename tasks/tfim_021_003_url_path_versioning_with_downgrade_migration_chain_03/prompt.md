# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule PathVersionApi.Migrations do
  @moduledoc """
  Versioning core for `PathVersionApi`.

  A single canonical latest representation (`"v3"`) is built from a stored user
  and older representations are produced by applying a descending downgrade
  migration chain (`v3 -> v2 -> v1`) rather than hand-written per-version
  renderers.
  """

  # Descending migration chain: latest first.
  @chain ["v3", "v2", "v1"]

  @doc """
  Returns the supported versions in ascending order, e.g. `["v1", "v2", "v3"]`.
  """
  @spec supported() :: [String.t()]
  def supported, do: Enum.reverse(@chain)

  @doc """
  Renders `user` under `id` for the requested `version`.

  Builds the canonical v3 document and applies each downgrade step needed to
  reach `version`.
  """
  @spec render(String.t(), String.t(), map()) :: map()
  def render(version, id, user) do
    user
    |> canonical(id)
    |> downgrade(version)
  end

  defp canonical(user, id) do
    %{
      id: id,
      name: %{first: user.first_name, last: user.last_name},
      email: user.email,
      created_at: user.created_at,
      country: user.country
    }
  end

  defp downgrade(doc, target) do
    target
    |> steps_to()
    |> Enum.reduce(doc, &apply_step/2)
  end

  defp steps_to(target) do
    idx = Enum.find_index(@chain, &(&1 == target))

    @chain
    |> Enum.take(idx + 1)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [from, to] -> {from, to} end)
  end

  defp apply_step({"v3", "v2"}, doc) do
    %{first: first, last: last} = doc.name

    doc
    |> Map.drop([:name, :country])
    |> Map.put(:first_name, first)
    |> Map.put(:last_name, last)
  end

  defp apply_step({"v2", "v1"}, doc) do
    full = doc.first_name <> " " <> doc.last_name

    doc
    |> Map.drop([:first_name, :last_name, :created_at])
    |> Map.put(:name, full)
  end
end

defmodule PathVersionApi.Router do
  @moduledoc """
  `Plug.Router` serving `GET /api/:version/users/:id`, where the API version is
  taken from the URL path and rendered via `PathVersionApi.Migrations`.

  An unsupported path version yields `400` before any user lookup; a valid
  version with an unknown id yields `404`. All responses are JSON.
  """

  use Plug.Router

  @users %{
    "1" => %{
      first_name: "Alice",
      last_name: "Smith",
      email: "alice@example.com",
      created_at: "2024-01-15T10:30:00Z",
      country: "US"
    },
    "2" => %{
      first_name: "Bob",
      last_name: "Jones",
      email: "bob@example.com",
      created_at: "2024-06-20T14:00:00Z",
      country: "GB"
    }
  }

  plug :match
  plug :dispatch

  get "/api/:version/users/:id" do
    supported = PathVersionApi.Migrations.supported()

    cond do
      version not in supported ->
        send_json(conn, 400, %{error: "unsupported version", supported: supported})

      true ->
        case Map.get(@users, id) do
          nil ->
            send_json(conn, 404, %{error: "not found"})

          user ->
            send_json(conn, 200, PathVersionApi.Migrations.render(version, id, user))
        end
    end
  end

  match _ do
    send_json(conn, 404, %{error: "not found"})
  end

  defp send_json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule PathVersionApi.RouterTest do
  use ExUnit.Case, async: false
  import Plug.Test

  @opts PathVersionApi.Router.init([])

  defp call(path) do
    PathVersionApi.Router.call(conn(:get, path), @opts)
  end

  defp json_body(conn), do: Jason.decode!(conn.resp_body)

  defp content_type(conn) do
    {"content-type", ct} = List.keyfind(conn.resp_headers, "content-type", 0)
    ct
  end

  # -------------------------------------------------------
  # v3 canonical shape (nested name + country)
  # -------------------------------------------------------

  test "v3 returns the canonical nested representation" do
    conn = call("/api/v3/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["name"] == %{"first" => "Alice", "last" => "Smith"}
    assert body["email"] == "alice@example.com"
    assert body["created_at"] == "2024-01-15T10:30:00Z"
    assert body["country"] == "US"
  end

  # -------------------------------------------------------
  # v2 downgrade (flatten name, drop country)
  # -------------------------------------------------------

  test "v2 flattens name and drops country" do
    # TODO
  end

  # -------------------------------------------------------
  # v1 downgrade (combine name, drop created_at)
  # -------------------------------------------------------

  test "v1 combines the name and drops created_at and country" do
    conn = call("/api/v1/users/1")

    assert conn.status == 200
    body = json_body(conn)

    assert body["id"] == "1"
    assert body["name"] == "Alice Smith"
    assert body["email"] == "alice@example.com"
    refute Map.has_key?(body, "first_name")
    refute Map.has_key?(body, "last_name")
    refute Map.has_key?(body, "created_at")
    refute Map.has_key?(body, "country")
  end

  test "each version yields a distinct key set" do
    keys = fn v -> "/api/#{v}/users/1" |> call() |> json_body() |> Map.keys() |> Enum.sort() end

    assert keys.("v1") == ["email", "id", "name"]
    assert keys.("v2") == ["created_at", "email", "first_name", "id", "last_name"]
    assert keys.("v3") == ["country", "created_at", "email", "id", "name"]
  end

  # -------------------------------------------------------
  # Unsupported version -> 400 (before user lookup)
  # -------------------------------------------------------

  test "unsupported path version returns 400" do
    conn = call("/api/v9/users/1")

    assert conn.status == 400
    body = json_body(conn)
    assert body["error"] =~ "unsupported"
    assert body["supported"] == ["v1", "v2", "v3"]
  end

  test "unsupported version returns 400 even for a missing user" do
    conn = call("/api/v9/users/999")
    assert conn.status == 400
  end

  # -------------------------------------------------------
  # Not found
  # -------------------------------------------------------

  test "valid version + missing user returns 404" do
    conn = call("/api/v2/users/999")
    assert conn.status == 404
    assert json_body(conn)["error"] =~ "not found"
  end

  # -------------------------------------------------------
  # Second user & content type
  # -------------------------------------------------------

  test "second user resolves through the chain in v1" do
    conn = call("/api/v1/users/2")
    body = json_body(conn)
    assert body["name"] == "Bob Jones"
    assert body["email"] == "bob@example.com"
  end

  test "second user has its own country in v3" do
    conn = call("/api/v3/users/2")
    assert json_body(conn)["country"] == "GB"
  end

  test "all responses are application/json" do
    for path <- ["/api/v1/users/1", "/api/v2/users/999", "/api/v9/users/1"] do
      assert content_type(call(path)) =~ "application/json"
    end
  end

  # -------------------------------------------------------
  # Migrations module used directly
  # -------------------------------------------------------

  test "supported/0 lists versions ascending" do
    assert PathVersionApi.Migrations.supported() == ["v1", "v2", "v3"]
  end

  test "render/3 is a pure downgrade of the canonical document" do
    user = %{
      first_name: "Zoe",
      last_name: "Lin",
      email: "zoe@example.com",
      created_at: "2023-03-03T00:00:00Z",
      country: "SG"
    }

    assert PathVersionApi.Migrations.render("v1", "42", user) ==
             %{id: "42", name: "Zoe Lin", email: "zoe@example.com"}
  end

  test "unmatched route returns 404" do
    conn = call("/api/v1/widgets/1")
    assert conn.status == 404
  end
end
```
