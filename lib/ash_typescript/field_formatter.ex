# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FieldFormatter do
  @moduledoc """
  Formatter-only field naming: converts a name with a formatter, without any
  resource or type context. Delegates to `AshRpc.FieldFormatter`.

  Codegen doesn't use this for client names. Those come from the manifest's
  decoration, read through `AshTypescript.Codegen.ClientNames`, so overrides
  such as `field_names` apply exactly as they do at runtime.
  """

  defdelegate format_field_name(field, formatter), to: AshRpc.FieldFormatter
end
