# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshTypescript.NpmInstall do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(_) do
    System.cmd("npm", ["install"], cd: "assets")
  end
end
