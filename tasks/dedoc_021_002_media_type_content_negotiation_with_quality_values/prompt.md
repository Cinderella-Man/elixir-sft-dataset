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
defmodule MediaVersionApi.Views.UserView do
  def render("v1", u), do: %{name: u.first_name <> " " <> u.last_name, email: u.email}

  def render("v2", u),
    do: %{
      first_name: u.first_name,
      last_name: u.last_name,
      email: u.email,
      created_at: u.created_at
    }
end

defmodule MediaVersionApi.Plugs.AcceptVersion do
  import Plug.Conn

  @vendor "application/vnd.acme."

  def init(opts), do: opts

  def call(conn, opts) do
    supported = Keyword.get(opts, :supported, ["v1", "v2"])
    default = Keyword.get(opts, :default, "v2")

    case get_req_header(conn, "accept") do
      [] -> assign(conn, :api_version, default)
      [accept | _] -> resolve(conn, accept, supported, default)
    end
  end

  defp resolve(conn, accept, supported, default) do
    version =
      accept
      |> parse_accept(default)
      |> Enum.filter(fn {v, _q} -> v in supported end)
      |> best_version()

    case version do
      nil ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(406, Jason.encode!(%{error: "unsupported version", supported: supported}))
        |> halt()

      v ->
        assign(conn, :api_version, v)
    end
  end

  defp parse_accept(accept, default) do
    accept
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_media_range(&1, default))
    |> Enum.reject(fn {v, q} -> is_nil(v) or q <= 0 end)
  end

  defp parse_media_range(range, default) do
    [type | params] = range |> String.split(";") |> Enum.map(&String.trim/1)
    {version_for(type, default), parse_q(params)}
  end

  defp version_for(type, default) do
    cond do
      String.starts_with?(type, @vendor) and String.ends_with?(type, "+json") ->
        type
        |> String.replace_prefix(@vendor, "")
        |> String.replace_suffix("+json", "")

      type in ["application/json", "application/*", "*/*"] ->
        default

      true ->
        nil
    end
  end

  defp parse_q(params) do
    Enum.find_value(params, 1.0, fn p ->
      case String.split(p, "=") do
        ["q", val] ->
          case Float.parse(val) do
            {f, _} -> f
            :error -> 1.0
          end

        _ ->
          nil
      end
    end)
  end

  defp best_version([]), do: nil

  defp best_version(list) do
    {{v, _q}, _idx} =
      list
      |> Enum.with_index()
      |> Enum.max_by(fn {{_v, q}, idx} -> {q, -idx} end)

    v
  end
end

defmodule MediaVersionApi.Router do
  use Plug.Router

  @users %{
    "1" => %{
      first_name: "Alice",
      last_name: "Smith",
      email: "alice@example.com",
      created_at: "2024-01-15T10:30:00Z"
    },
    "2" => %{
      first_name: "Bob",
      last_name: "Jones",
      email: "bob@example.com",
      created_at: "2024-06-20T14:00:00Z"
    }
  }

  plug(MediaVersionApi.Plugs.AcceptVersion, supported: ["v1", "v2"], default: "v2")
  plug(:match)
  plug(:dispatch)

  get "/api/users/:id" do
    version = conn.assigns.api_version

    case Map.get(@users, id) do
      nil ->
        send_error(conn, 404, %{error: "not found"})

      user ->
        body = MediaVersionApi.Views.UserView.render(version, user)

        conn
        |> put_resp_content_type("application/vnd.acme.#{version}+json")
        |> send_resp(200, Jason.encode!(body))
    end
  end

  match _ do
    send_error(conn, 404, %{error: "not found"})
  end

  defp send_error(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Jason.encode!(body))
  end
end
```
