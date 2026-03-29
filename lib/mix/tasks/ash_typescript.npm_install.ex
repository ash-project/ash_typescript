# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshTypescript.NpmInstall do
  @moduledoc false
  use Mix.Task

  @impl true
  def run(args) do
    package_manager =
      if args == ["--bun"] do
        "bun"
      else
        "npm"
      end

    System.cmd(package_manager, ["install"], cd: "assets")
  end
end
