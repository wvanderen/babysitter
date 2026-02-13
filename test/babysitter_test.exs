defmodule BabysitterTest do
  use ExUnit.Case
  doctest Babysitter

  test "greets the world" do
    assert Babysitter.hello() == :world
  end
end
