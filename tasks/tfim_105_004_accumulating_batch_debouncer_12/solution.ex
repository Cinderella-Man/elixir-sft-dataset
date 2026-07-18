  test "start_link/1 registers under a custom :name alongside the default process" do
    pid = start_supervised!({BatchDebouncer, [name: :batch_debouncer_alt]}, id: :bd_alt)

    assert Process.whereis(:batch_debouncer_alt) == pid
    assert is_pid(pid)
    default = Process.whereis(BatchDebouncer)
    assert is_pid(default)
    assert default != pid
  end