  @doc """
  Handles a poll request: authenticates, subscribes, and either replays buffered
  events, blocks for a live notification, or times out with a 204 response.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    server = Keyword.fetch!(opts, :notifications_server)
    timeout = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    conn = fetch_query_params(conn)

    case conn.assigns[:user_id] do
      nil ->
        send_resp(conn, 401, "unauthorized")

      user_id ->
        cursor = parse_cursor(conn.query_params["since"])
        Notifications.subscribe(server, user_id)

        case Notifications.events_since(server, user_id, cursor) do
          [] -> wait_for_notification(conn, timeout, cursor)
          events -> respond_with_events(conn, events)
        end
    end
  end