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