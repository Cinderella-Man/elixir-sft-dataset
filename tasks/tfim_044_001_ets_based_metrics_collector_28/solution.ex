  test "a negative increment amount never lowers an existing counter" do
    Metrics.increment(:downward, 10)

    try do
      Metrics.increment(:downward, -4)
    rescue
      _ -> :ok
    catch
      _, _ -> :ok
    end

    assert Metrics.get(:downward) >= 10
  end