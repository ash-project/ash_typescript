# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

ExUnit.configure(exclude: [:generates_warnings])
ExUnit.start()

# Ensure all test resources are loaded

# Initialize ETS tables by running a simple query on each resource
# This ensures all ETS tables are created before tests run
for resource <- [
      AshTypescript.Test.User,
      AshTypescript.Test.Todo,
      AshTypescript.Test.TodoComment,
      AshTypescript.Test.NotExposed
    ] do
  try do
    Ash.read!(resource, authorize?: false)
  rescue
    _ -> :ok
  end
end
