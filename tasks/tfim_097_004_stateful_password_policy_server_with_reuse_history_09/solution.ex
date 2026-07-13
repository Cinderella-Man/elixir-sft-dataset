  test "default :history_size remembers exactly five passwords" do
    {:ok, pid} = PasswordPolicy.start_link([])

    for pw <- ~w(P1!aaaaa P2!bbbbb P3!ccccc P4!ddddd P5!eeeee) do
      assert PasswordPolicy.set_password(pid, "operator", pw) == :ok
    end

    # Five accepted passwords all fit inside the default bound.
    assert PasswordPolicy.history_count(pid, "operator") == 5

    # A sixth evicts the oldest but keeps the bound at five.
    assert PasswordPolicy.set_password(pid, "operator", "P6!fffff") == :ok
    assert PasswordPolicy.history_count(pid, "operator") == 5

    # The second-oldest is still remembered; the oldest has been evicted.
    assert PasswordPolicy.set_password(pid, "operator", "P2!bbbbb") ==
             {:error, [:reused_password]}

    assert PasswordPolicy.set_password(pid, "operator", "P1!aaaaa") == :ok
  end