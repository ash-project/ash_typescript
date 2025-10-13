# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
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
