# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.FormatterSourceTest do
  use ExUnit.Case, async: false

  test "AshTypescript formatter accessors read the manifest, not runtime config" do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :output_field_formatter,
      :input_field_formatter
    ])

    Application.put_env(:ash_typescript, :output_field_formatter, :pascal_case)
    Application.put_env(:ash_typescript, :input_field_formatter, :snake_case)

    assert AshTypescript.output_field_formatter() ==
             AshRpc.Manifest.output_formatter(AshTypescript.manifest())

    assert AshTypescript.input_field_formatter() ==
             AshRpc.Manifest.input_formatter(AshTypescript.manifest())

    assert AshTypescript.output_field_formatter() == :camel_case
  end
end
