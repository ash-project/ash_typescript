# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.TestApp do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = []

    opts = [strategy: :one_for_one, name: AshTypescript.TestApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
