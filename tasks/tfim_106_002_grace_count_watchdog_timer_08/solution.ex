  test "misses for an unknown name returns an error" do
    assert {:error, :not_registered} = GraceWatchdog.misses(:nope)
  end