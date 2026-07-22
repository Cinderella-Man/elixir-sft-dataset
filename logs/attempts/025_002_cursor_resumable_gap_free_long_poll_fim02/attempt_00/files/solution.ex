  defp wait_for_notification(conn, timeout, cursor) do
    receive do
      {:notification, seq, payload} ->
        respond_with_events(conn, [{seq, payload}])
    after
      timeout ->
        conn
        |> put_resp_header("x-notification-cursor", Integer.to_string(cursor))
        |> send_resp(204, "")
    end
  end