# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.EmptyManifestCodegenTest do
  # Mutates the global :manifest config, so must not run async.
  use ExUnit.Case, async: false

  @moduletag :ash_typescript

  defmodule EmptyManifest do
    use AshTypescript.Manifest, otp_app: :ash_typescript, domains: []
  end

  test "codegen terminates and succeeds with an empty manifest (fresh install)" do
    # A fresh install has a manifest but no domains, controllers, or channels yet.
    overrides = [manifest: EmptyManifest, typed_controllers: [], typed_channels: []]

    previous =
      Enum.map(overrides, fn {key, value} ->
        prev = Application.get_env(:ash_typescript, key)
        Application.put_env(:ash_typescript, key, value)
        {key, prev}
      end)

    on_exit(fn ->
      Enum.each(previous, fn {key, prev} ->
        Application.put_env(:ash_typescript, key, prev)
      end)
    end)

    task =
      Task.async(fn ->
        # A fresh install has no ash_domains configured either, so resource
        # discovery must come up empty too — use an app with no domains.
        AshTypescript.Codegen.Orchestrator.generate(:fresh_install_no_domains_app, [])
      end)

    case Task.yield(task, 10_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, files}} ->
        assert is_map(files)

      {:ok, {:error, message}} ->
        flunk("codegen errored on empty manifest: #{inspect(message)}")

      nil ->
        flunk("codegen hung on an empty manifest (infinite loop)")

      {:exit, reason} ->
        flunk("codegen crashed on empty manifest: #{inspect(reason)}")
    end
  end
end
