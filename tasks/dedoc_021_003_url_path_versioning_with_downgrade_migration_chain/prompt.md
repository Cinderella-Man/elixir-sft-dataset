# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule PathVersionApi.Migrations do
  # Descending migration chain: latest first.
  @chain ["v3", "v2", "v1"]

  def supported, do: Enum.reverse(@chain)

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

  plug(:match)
  plug(:dispatch)

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
