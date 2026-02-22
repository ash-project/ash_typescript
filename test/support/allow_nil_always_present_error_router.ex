# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.AllowNilAlwaysPresentErrorRouter do
  @moduledoc """
  Test router that makes :tab a path parameter for :provider_page.

  Since :tab has `allow_nil?: true` (the default) but is always a path param here,
  the validation should raise an error.
  """
  use Phoenix.Router

  scope "/" do
    get("/auth/providers/:provider/:tab", AshTypescript.Test.SessionController, :provider_page)
  end
end
