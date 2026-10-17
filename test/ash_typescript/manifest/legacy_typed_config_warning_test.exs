# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.LegacyTypedConfigWarningTest do
  # Mutates app env, so not async
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  setup do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :typed_controllers,
      :typed_channels
    ])

    :ok
  end

  test "a leftover typed config key warns at manifest compile time and is not used" do
    Application.put_env(:ash_typescript, :typed_controllers, [AshTypescript.Test.Session])
    Application.put_env(:ash_typescript, :typed_channels, [AshTypescript.Test.OrgChannel])

    module = AshTypescript.Manifest.LegacyTypedConfigWarningTest.Compiled

    stderr =
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

    assert stderr =~ "config :ash_typescript, :typed_controllers"
    assert stderr =~ "typed_controllers:"
    assert stderr =~ "config :ash_typescript, :typed_channels"
    assert stderr =~ "typed_channels:"

    assert Spark.Dsl.Extension.get_persisted(module, :typed_controllers) == []
    assert Spark.Dsl.Extension.get_persisted(module, :typed_channels) == []
  end

  test "no warning when the keys are unset" do
    Application.delete_env(:ash_typescript, :typed_controllers)
    Application.delete_env(:ash_typescript, :typed_channels)

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Module.create(
          AshTypescript.Manifest.LegacyTypedConfigWarningTest.Clean,
          quote do
            use AshTypescript.Manifest,
              otp_app: :ash_typescript,
              domains: [AshTypescript.Test.SecondDomain]
          end,
          Macro.Env.location(__ENV__)
        )
      end)

    refute stderr =~ "typed_controllers"
    refute stderr =~ "typed_channels"
  end
end
