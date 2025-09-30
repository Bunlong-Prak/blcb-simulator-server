defmodule BlSimulatorWeb.ErrorJSONTest do
  use BlSimulatorWeb.ConnCase, async: true

  test "renders 404" do
    assert BlSimulatorWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert BlSimulatorWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
