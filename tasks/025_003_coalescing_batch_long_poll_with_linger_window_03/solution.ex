  defp wait_for_batch(conn, timeout, linger) do
    receive do
      {:notification, payload} ->
        batch = drain([payload], linger)
        respond(conn, batch)
    after
      timeout ->
        send_resp(conn, 204, "")
    end
  end