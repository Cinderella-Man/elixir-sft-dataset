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
defmodule Notifications do
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Registry.start_link(keys: :duplicate, name: name)
  end

  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def subscribe(server \\ __MODULE__, user_id, channel) do
    {:ok, _pid} = Registry.register(server, {user_id, channel}, nil)
    :ok
  end

  def publish(server \\ __MODULE__, user_id, channel, payload) do
    Registry.dispatch(server, {user_id, channel}, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, channel, payload})
    end)

    :ok
  end
end

defmodule NotificationPoller do
  import Plug.Conn

  @default_timeout_ms 30_000

  def init(opts), do: opts

  def call(conn, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    conn = fetch_query_params(conn)

    case conn.assigns[:user_id] do
      nil ->
        send_resp(conn, 401, "unauthorized")

      user_id ->
        case parse_channels(conn.query_params["channels"]) do
          [] ->
            send_resp(conn, 400, "no channels")

          channels ->
            for channel <- channels, do: Notifications.subscribe(server, user_id, channel)
            wait_for_notification(conn, timeout)
        end
    end
  end

  defp wait_for_notification(conn, timeout) do
    receive do
      {:notification, channel, payload} ->
        body = Jason.encode!(%{"channel" => channel, "payload" => payload})

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, body)
    after
      timeout ->
        send_resp(conn, 204, "")
    end
  end

  defp parse_channels(nil), do: []
  defp parse_channels(str), do: String.split(str, ",", trim: true)
end

defmodule NotificationRouter do
  use Plug.Router, copy_opts_to_assign: :poller_opts

  plug(:match)
  plug(:dispatch)

  get "/api/notifications/poll" do
    opts = conn.assigns.poller_opts
    NotificationPoller.call(conn, NotificationPoller.init(opts))
  end

  match _ do
    send_resp(conn, 404, "not found")
  end
end
```
