# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.LegacyTypeConfigWarningTest do
  # Mutates app env, so not async
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  alias AshTypescript.Manifest.LegacyTypeConfigWarningTest, as: T

  setup do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([:type_mapping_overrides])
    :ok
  end

  defp compile_manifest(module) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      Module.create(
        module,
        quote do
          use AshTypescript.Manifest,
            otp_app: :ash_typescript,
            domains: [AshTypescript.Test.SecondDomain]
        end,
        Macro.Env.location(__ENV__)
      )
    end)
  end

  test "a leftover type_mapping_overrides key warns at manifest compile time" do
    Application.put_env(:ash_typescript, :type_mapping_overrides, [
      {AshTypescript.Test.CustomIdentifier, "string"}
    ])

    stderr = compile_manifest(T.Compiled)

    assert stderr =~
             "config :ash_typescript, :type_mapping_overrides is no longer read and is ignored."

    assert stderr =~ "custom_types"
  end

  test "the leftover key is not read" do
    Application.put_env(:ash_typescript, :type_mapping_overrides, [
      {AshTypescript.Test.CustomIdentifier, "Overridden"}
    ])

    _ = compile_manifest(T.NotRead)

    # The test manifest's `scalar` entry maps it.
    assert AshTypescript.Codegen.get_ts_type(%{
             type: AshTypescript.Test.CustomIdentifier,
             constraints: []
           }) == "string"
  end

  test "no warning when the key is unset" do
    Application.delete_env(:ash_typescript, :type_mapping_overrides)

    refute compile_manifest(T.Clean) =~ "type_mapping_overrides"
  end
end
