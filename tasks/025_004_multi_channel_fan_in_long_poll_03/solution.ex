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