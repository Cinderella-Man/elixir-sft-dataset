  test "start_link/1 registers under the module name by default and rejects a duplicate" do
    default = Process.whereis(Debouncer)
    assert is_pid(default)

    # The setup instance was started with no :name, so it must own the default
    # registration; a second start under the same name is rejected.
    assert {:error, {:already_started, ^default}} = Debouncer.start_link([])
  end