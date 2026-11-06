# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.RestrictedSchemaAgreementTest do
  # The restricted schemas agree with what ash_rpc enforces. For every
  # restricted rpc_action of the test domain, the selections
  # `test/ts/shouldPass/restrictedSchemaAgreement.ts` makes (which the types
  # accept, `npm run compileShouldPass`) are accepted by the runtime, and the
  # loads `test/ts/shouldFail/restrictedSchemaAgreement.ts` makes (which the
  # types reject, `npm run compileShouldFail`) are rejected as load_denied or
  # load_not_allowed.
  use ExUnit.Case, async: true

  import AshTypescript.Test.TestHelpers, only: [parse_selection: 2, rpc_runtime: 0]

  alias AshTypescript.Test.TsActionCallExtractor

  @moduletag :ash_typescript

  @accepted "test/ts/shouldPass/restrictedSchemaAgreement.ts"
  @rejected "test/ts/shouldFail/restrictedSchemaAgreement.ts"

  @external_resource @accepted
  @external_resource @rejected

  setup_all do
    %{accepted: calls!(@accepted), rejected: calls!(@rejected)}
  end

  test "both files sample every restricted rpc_action of the test domain", %{
    accepted: accepted,
    rejected: rejected
  } do
    restricted =
      rpc_runtime().entrypoints
      |> Map.values()
      |> Enum.filter(&(&1.domain == AshTypescript.Test.Domain and &1.load_restrictions != :none))
      |> MapSet.new(& &1.name)

    assert MapSet.size(restricted) > 0
    assert MapSet.new(accepted, & &1.action_name) == restricted
    assert MapSet.new(rejected, & &1.action_name) == restricted
  end

  test "the runtime accepts every selection the types accept", %{accepted: accepted} do
    for %{action_name: action, config: %{"fields" => fields}} <- accepted do
      assert {:ok, _request} = parse_selection(action, fields),
             "#{action} rejected #{inspect(fields)}"
    end
  end

  test "the runtime rejects every load the types reject", %{rejected: rejected} do
    for %{action_name: action, config: %{"fields" => fields}} <- rejected do
      assert {:error, {reason, [_path]}} = parse_selection(action, fields),
             "#{action} accepted #{inspect(fields)}"

      assert reason in [:load_denied, :load_not_allowed],
             "#{action} rejected #{inspect(fields)} as #{inspect(reason)}"
    end
  end

  # Every call of the file, or a failure naming the calls the extractor
  # couldn't parse.
  defp calls!(path) do
    content = File.read!(path)
    calls = TsActionCallExtractor.extract_calls(content)
    awaits = length(Regex.scan(~r/await\s+\w+\(/, content))

    if length(calls) != awaits do
      raise "#{path}: extracted #{length(calls)} of #{awaits} calls"
    end

    calls
  end
end
