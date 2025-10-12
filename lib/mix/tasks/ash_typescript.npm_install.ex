# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
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
