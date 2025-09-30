defmodule BlSimulatorDevTest do
  use ExUnit.Case
  doctest BlSimulatorDev

  test "greets the world" do
    assert BlSimulatorDev.hello() == :world
  end
end
