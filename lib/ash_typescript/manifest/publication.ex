# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Publication do
  @moduledoc """
  A typed channel's declared event and its publication's `returns` type,
  stored under `manifest.custom.ash_typescript.publications` keyed by
  `{channel_module, resource, event}`. Two channels may declare the same
  publication; each gets its own entry. `returns` is `nil` when the
  publication declares no `returns` (payloads pass through unformatted, and
  codegen emits `unknown`).
  """

  @type t :: %__MODULE__{
          channel_module: module(),
          resource: module(),
          event: String.t(),
          returns: Ash.Info.Manifest.Type.t() | nil
        }

  defstruct [:channel_module, :resource, :event, :returns]
end
