# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.LegacyTypeConfigWarningTest do
  # Mutates app env, so not async
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  alias AshTypescript.Manifest.LegacyTypeConfigWarningTest, as: T

  setup do
    AshTypescript.Test.TestHelpers.restore_application_env_on_exit([
      :type_mapping_overrides,
      :zod_mapping_overrides,
      :valibot_mapping_overrides
    ])

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

    # The test manifest's `scalar` entry maps and names it.
    assert AshTypescript.Codegen.get_ts_type(%{
             type: AshTypescript.Test.CustomIdentifier,
             constraints: []
           }) == "CustomIdentifier"
  end

  for {key, option} <- [zod_mapping_overrides: "zod", valibot_mapping_overrides: "valibot"] do
    test "a leftover #{key} key warns at manifest compile time" do
      Application.put_env(:ash_typescript, unquote(key), [
        {AshTypescript.Test.CustomIdentifier, "schema"}
      ])

      stderr = compile_manifest(Module.concat(T, Macro.camelize("#{unquote(key)}")))

      assert stderr =~
               "config :ash_typescript, #{inspect(unquote(key))} is no longer read and is ignored."

      assert stderr =~ "custom_types"
      # Names the entry option that replaces it.
      assert stderr =~ "#{unquote(option)}: "
    end
  end

  test "a leftover zod_mapping_overrides key is not read" do
    Application.put_env(:ash_typescript, :zod_mapping_overrides, [
      {AshTypescript.Test.CustomIdentifier, "Overridden"}
    ])

    resolved =
      Ash.Info.Manifest.Generator.TypeResolver.resolve(AshTypescript.Test.CustomIdentifier, [])

    # The test manifest's `scalar` entry names the schema.
    assert AshTypescript.Codegen.SchemaCore.get_type(
             AshTypescript.Codegen.ZodSchemaGenerator,
             resolved
           ) == "CustomZodSchemas.objectId"
  end

  test "no warning when the keys are unset" do
    for key <- [:type_mapping_overrides, :zod_mapping_overrides, :valibot_mapping_overrides] do
      Application.delete_env(:ash_typescript, key)
    end

    stderr = compile_manifest(T.Clean)
    refute stderr =~ "type_mapping_overrides"
    refute stderr =~ "zod_mapping_overrides"
    refute stderr =~ "valibot_mapping_overrides"
  end
end
