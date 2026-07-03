def call(conn, opts) do
  server = Keyword.fetch!(opts, :notifications_server)
  timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
  linger = Keyword.get(opts, :linger_ms, @default_linger_ms)

  case conn.assigns[:user_id] do
    nil ->
      send_resp(conn, 401, "unauthorized")

    user_id ->
      Notifications.subscribe(server, user_id)
      wait_for_batch(conn, timeout, linger)
  end
end