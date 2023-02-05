defmodule BffTest do
  use ExUnit.Case
  doctest Bff

  test "greets the world" do
    assert Bff.hello() == :world
  end
end
