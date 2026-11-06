# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.HandleOptsTest.Tracer do
  @moduledoc false
  # Sends the compile-time events of the manifest module's body to the
  # process compiling it: `Application.compile_env/3` reads, and remote
  # `module_info/1` calls (the compile edges `handle_opts/1` and
  # `DecorateManifest` inject).
  def trace({:compile_env, app, path, _return}, %{function: nil} = env),
    do: report(env, {:compile_env, app, path})

  def trace({:remote_function, _meta, module, :module_info, 1}, %{function: nil} = env),
    do: report(env, {:edge, module})

  def trace(_event, _env), do: :ok

  defp report(%{module: module}, event) do
    send(self(), {__MODULE__, module, event})
    :ok
  end
end

defmodule AshTypescript.Manifest.HandleOptsTest do
  # The compiler tracer option is global, so the module runs alone.
  use ExUnit.Case, async: false

  alias AshTypescript.Manifest.HandleOptsTest.Tracer

  @moduletag :ash_typescript

  # Compiles a manifest module with `opts` and returns the events its body
  # traced.
  defp compile_traced(module, opts) do
    quoted =
      quote do
        defmodule unquote(module) do
          use AshTypescript.Manifest, unquote(opts)
          unquote(AshTypescript.Test.InlineManifest.app_custom_types())
        end
      end

    previous = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [Tracer | previous])

    try do
      ExUnit.CaptureIO.with_io(:stderr, fn -> Code.compile_quoted(quoted) end)
    after
      Code.put_compiler_option(:tracers, previous)
    end

    collect(module, [])
  end

  defp collect(module, events) do
    receive do
      {Tracer, ^module, event} -> collect(module, [event | events])
    after
      0 -> events |> Enum.reverse() |> Enum.uniq()
    end
  end

  setup_all do
    events =
      compile_traced(AshTypescript.Manifest.HandleOptsTest.ExplicitManifest,
        otp_app: :ash_typescript,
        domains: [AshTypescript.Test.Domain],
        typed_controllers: [AshTypescript.Test.Session],
        typed_channels: [AshTypescript.Test.OrgChannel]
      )

    %{events: events}
  end

  test "handle_opts/1 adds compile edges and compile_env reads", %{events: events} do
    assert {:compile_env, :ash_typescript, [:output_field_formatter]} in events
    assert {:compile_env, :ash_typescript, [:not_found_error?]} in events

    assert {:edge, AshTypescript.Test.Domain} in events
    assert {:edge, AshTypescript.Test.Session} in events
    assert {:edge, AshTypescript.Test.OrgChannel} in events

    # Explicit domains: the :ash_domains config isn't read.
    refute Enum.any?(events, &match?({:compile_env, _app, [:ash_domains]}, &1))
  end

  test "without explicit domains, the otp_app's :ash_domains are edges and tracked" do
    events =
      compile_traced(AshTypescript.Manifest.HandleOptsTest.AppManifest, otp_app: :ash_typescript)

    assert {:compile_env, :ash_typescript, [:ash_domains]} in events

    for domain <- Application.fetch_env!(:ash_typescript, :ash_domains) do
      assert {:edge, domain} in events
    end
  end

  test "DecorateManifest tracks declared type modules", %{events: events} do
    # Fields from composite_types/1, fields and alias from callbacks, an
    # aliased NewType.
    for module <- [
          AshTypescript.Test.CompositePoint,
          AshTypescript.Test.Theme,
          AshTypescript.Test.TaskStats
        ] do
      assert {:edge, module} in events, "no compile edge on #{inspect(module)}"
    end
  end
end
