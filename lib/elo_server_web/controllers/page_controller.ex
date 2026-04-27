defmodule EloServerWeb.PageController do
  use EloServerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
