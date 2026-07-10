  test "rejects files larger than 5MB with 413", %{opts: opts} do
    # The file content alone already exceeds the 5MB request-body limit.
    big_content = String.duplicate("x", 5_242_881)

    case call_upload(opts, "huge.csv", big_content) do
      {:sent_and_reraised, status} ->
        # `Plug.ErrorHandler` style: the response was sent (confirmed by the
        # adapter) but its body is unobservable once the error re-raises, so
        # only the 413 status — carried by the exception — can be asserted.
        assert status == 413

      conn ->
        assert conn.status == 413
        body = json_body(conn)
        assert body["error"] =~ "too large" or body["error"] =~ "Too large"
        assert body["max_bytes"] == 5_242_880
    end
  end