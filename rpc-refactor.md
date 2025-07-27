# AshTypescript RPC Refactoring Plan

## Executive Summary

This document outlines a comprehensive plan to **completely refactor** the AshTypescript RPC processing pipeline. While the current implementation has the right architectural foundation, this refactoring will **replace the existing system entirely** with a clean, optimized implementation focused purely on the new architecture. No backwards compatibility will be maintained - this is a complete rewrite of the RPC processing layer.

## Current State Analysis

### Implemented Architecture ✅

The desired processing flow is already implemented in `lib/ash_typescript/rpc.ex`:

1. **Input Formatting** (lines 168-173): `FieldParser.parse_requested_fields()` converts client field names to atoms
2. **Input Data Formatting** (lines 190-194): `FieldFormatter.parse_input_fields()` converts input data keys  
3. **Action Execution** (lines 200-274): Ash operations use atom keys consistently
4. **Result Filtering** (lines 280-285): `ResultProcessorNew.extract_fields()` filters with atom keys
5. **Output Formatting**: `format_final_result()` applies output formatting as final step

### Key Strengths

- **Clean Separation**: Field parsing, action execution, and result processing are well-separated
- **Template-Driven**: Pre-computed extraction templates eliminate runtime complexity
- **Unified Format**: All internal processing uses atom keys consistently
- **Bidirectional Formatting**: Clean conversion between client and server field formats

### Complete Replacement Strategy

1. **Remove All Legacy Code**: Complete removal of existing RPC implementation
2. **Performance-Optimized Design**: Build optimization into the core architecture
3. **Strict-Only Operation**: No permissive modes, fail fast on all invalid inputs
4. **Clean Architecture**: Single-responsibility modules with clear data flow
5. **Production-Grade Error Handling**: Comprehensive error coverage with detailed messages

## Implementation Plan

### Phase 1: Core Architecture Replacement (Week 1)

#### 1.1 Complete RPC Pipeline Rewrite

**Objective**: Replace the entire RPC processing pipeline with the new architecture.

**Tasks**:
- [ ] **Replace `AshTypescript.Rpc.run_action/3`** with clean implementation:
  - Pure functional pipeline: `parse_input -> execute_action -> filter_result -> format_output`
  - Remove all legacy code paths and workarounds
  - Implement strict error handling throughout
- [ ] **Rewrite field processing logic**:
  - Input field parsing with mandatory validation
  - Atom-based internal processing only
  - Template-driven result extraction
- [ ] **Clean up supporting modules**:
  - Streamline `FieldParser` for new architecture only
  - Optimize `ResultProcessorNew` for performance
  - Remove deprecated helper functions

**Test Categories**:
```elixir
# 1. Simple field flow
client_fields = ["firstName", "lastName"] 
# Should produce: [:first_name, :last_name] internally
# Should return: %{"firstName" => "John", "lastName" => "Doe"}

# 2. Complex nested flow  
client_fields = [%{"user" => ["firstName", %{"profile" => ["displayName"]}]}]
# Should handle nested conversion throughout pipeline

# 3. Mixed field types
client_fields = ["id", %{"metadata" => ["category"]}, %{"calculations" => %{"fullName" => %{"fields" => ["firstName"]}}}]
```

**Success Criteria**:
- New implementation handles all field types correctly
- 50%+ performance improvement over current implementation
- Zero tolerance for invalid field requests (fail fast)
- Clean, readable code with obvious data flow

#### 1.2 Aggressive Field Validation Implementation

**Objective**: Implement strict field validation with zero tolerance for invalid requests.

**Tasks**:
- [ ] **Remove permissive field handling**: No more silent skipping of unknown fields
- [ ] **Implement fail-fast validation**: Invalid field requests should error immediately
- [ ] **Strict formatter validation**: Ensure formatters are correctly configured and compatible
- [ ] **Comprehensive error messages**: Clear, actionable error messages for all failure modes

**Implementation**:
```elixir
defmodule AshTypescript.FieldFormatterValidation do
  def validate_formatter_compatibility(input_formatter, output_formatter) do
    # Test round-trip conversion for common field names
    test_fields = ["firstName", "user_id", "displayName", "createdAt"]
    
    Enum.all?(test_fields, fn original_field ->
      internal_field = FieldFormatter.parse_input_field(original_field, input_formatter)
      output_field = FieldFormatter.format_field(internal_field, output_formatter)
      original_field == output_field
    end)
  end
end
```

#### 1.3 Performance-First Implementation

**Objective**: Build performance optimizations into the core architecture.

**Tasks**:
- [ ] **Memory-efficient processing**: Single-pass field parsing and template building
- [ ] **CPU optimization**: Fast-path common operations, minimize pattern matching overhead
- [ ] **Streaming extraction**: Process large result sets without loading everything into memory
- [ ] **Benchmark-driven development**: Measure every change, target 50%+ improvement

### Phase 2: Advanced Features & Optimization (Week 2)

#### 2.1 Advanced Field Type Support

**Objective**: Implement clean, optimized support for all advanced field types.

**Approach**: Build each field type handler from scratch with the new architecture in mind.

**Implementation**:
```elixir
defmodule AshTypescript.Rpc.FieldParser.V2 do
  @doc """
  Clean field parser implementation - no legacy support.
  Always fails fast on invalid fields.
  """
  def parse_requested_fields(fields, resource, formatter) do
    # No options - always strict, always validated
    context = Context.new(resource, formatter)
    
    {select, load, template} = 
      Enum.reduce(fields, {[], [], ExtractionTemplate.new()}, fn field, acc ->
        case process_field_strict(field, context) do
          {:error, reason} -> 
            raise ArgumentError, "Invalid field request: #{reason}"
          {:ok, result} -> 
            merge_field_result(result, acc)
        end
      end)
    
    {Enum.reverse(select), Enum.reverse(load), template}
  end
  
  defp process_field_strict(field, context) do
    # Always validate, never skip unknown fields
    case classify_field_strict(field, context) do
      :unknown -> {:error, "Unknown field '#{field}' for resource #{context.resource}"}
      classification -> {:ok, build_field_result(classification, field, context)}
    end
  end
end
```

#### 2.2 Clean Union & Embedded Resource Handling

**Tasks**:
- [ ] **Rewrite union field selection**: Clean, type-safe implementation
- [ ] **Optimize embedded resource processing**: Eliminate redundant field traversal
- [ ] **Streamline calculation handling**: Unified approach for simple and complex calculations
- [ ] **TypedStruct optimization**: Direct field access without intermediate conversions

### Phase 3: Testing & Validation (Week 3)

#### 3.1 Comprehensive Test Suite for New Architecture

**Objective**: Build complete test coverage for the new implementation only.

**Strategy**: Test the new architecture thoroughly without any reference to old behavior.
**Tasks**:
- [ ] **Pure new architecture tests**: Test only the new implementation
- [ ] **Performance benchmarks**: Ensure 50%+ improvement over baseline
- [ ] **Stress testing**: Large field lists, complex nested structures
- [ ] **Error condition testing**: Validate strict error handling

**Test Categories**:
```elixir
defmodule AshTypescript.Rpc.NewArchitectureTest do
  # Test the new implementation in isolation
  test "strict field validation fails fast" do
    assert_raise ArgumentError, ~r/Unknown field/, fn ->
      parse_fields(["invalid_field"], Todo, :camel_case)
    end
  end
  
  test "performance improvement over baseline" do
    {time, _result} = :timer.tc(fn -> 
      parse_complex_field_list(large_field_list()) 
    end)
    
    assert time < baseline_time() * 0.5  # 50% improvement required
  end
end
```

#### 3.2 Integration Testing for Complete Pipeline

**Tasks**:
- [ ] **End-to-end pipeline validation**: Client input through formatted output
- [ ] **All field type combinations**: Test complex scenarios with mixed field types
- [ ] **Formatter integration**: Ensure clean input/output formatting throughout
- [ ] **Resource compatibility**: Test with all resource types in test suite

**Success Metrics**:
- Zero test failures on new architecture
- 100% test coverage for new implementation
- All performance benchmarks exceed targets
- Clean, maintainable test code

### Phase 4: Production Readiness (Week 4)

#### 4.1 Production Hardening

**Tasks**:
- [ ] **Error handling completeness**: Ensure all edge cases are covered
- [ ] **Resource cleanup**: Verify no memory leaks or resource issues
- [ ] **Concurrency safety**: Test under concurrent load
- [ ] **Configuration validation**: Ensure all configurations are validated at startup

**Implementation**:
```elixir
defmodule AshTypescript.Rpc.V2 do
  @doc """
  Clean RPC implementation with no legacy support.
  
  Pipeline: parse_input -> execute_action -> filter_result -> format_output
  
  - Always strict field validation
  - Performance-optimized throughout
  - Clean error handling with detailed messages
  - Self-documenting code structure
  """
  def run_action(otp_app, conn, params) do
    with {:ok, parsed_request} <- parse_request_strict(params),
         {:ok, ash_result} <- execute_ash_action(parsed_request, conn),
         {:ok, filtered_result} <- filter_result_fields(ash_result, parsed_request),
         {:ok, formatted_result} <- format_output(filtered_result, parsed_request) do
      {:ok, formatted_result}
    else
      {:error, reason} -> {:error, build_error_response(reason)}
    end
  end
end
```

#### 4.2 Deployment & Monitoring

**Tasks**:
- [ ] **Performance monitoring**: Add telemetry events for key operations
- [ ] **Error tracking**: Comprehensive error logging and tracking
- [ ] **Health checks**: Validate RPC functionality in production
- [ ] **Documentation**: Clear, concise documentation for the new architecture

### Phase 5: Cleanup & Future-Proofing (Week 5)

#### 5.1 Legacy Code Removal

**Tasks**:
- [ ] **Remove old RPC implementation**: Delete all unused legacy code
- [ ] **Clean up dead imports**: Remove references to old modules
- [ ] **Update tests**: Remove any tests for old behavior
- [ ] **Documentation cleanup**: Ensure docs reflect only new architecture

#### 5.2 Architecture Future-Proofing

**Tasks**:
- [ ] **Extension points**: Design clean interfaces for future field types
- [ ] **Performance headroom**: Ensure architecture can handle future growth
- [ ] **Maintainability**: Code structure that's easy to extend and modify
- [ ] **Testing framework**: Test patterns that work for future changes

**Final Architecture**:
```elixir
# Clean, focused implementation
defmodule AshTypescript.Rpc.V2.Pipeline do
  @moduledoc "Pure functional RPC pipeline - no legacy support"
  
  def process_request(request) do
    request
    |> parse_fields_strict()
    |> execute_ash_action()
    |> filter_result_fields()
    |> format_output()
  end
  
  # Each step is a pure function with clear inputs/outputs
  # No side effects, easy to test, easy to understand
  # Performance optimized from the ground up
end
```

## Testing Strategy

### New Architecture Testing (No Legacy Compatibility)

#### 1. Clean Implementation Tests
- **New FieldParser**: Test only the new strict implementation
- **New ResultProcessor**: Performance-optimized field extraction
- **New Pipeline**: End-to-end testing of the complete rewrite

#### 2. Strict Validation Tests
- **Fail-Fast Behavior**: All invalid requests should error immediately
- **Error Message Quality**: Clear, actionable error messages
- **No Silent Failures**: Zero tolerance for unknown fields

#### 3. Performance-First Tests
- **Benchmark Requirements**: 50%+ improvement over baseline required
- **Memory Efficiency**: Single-pass processing, minimal allocations
- **CPU Optimization**: Fast-path common operations

#### 4. Production Readiness Tests
- **Stress Testing**: Large payloads, complex nested structures
- **Concurrency**: Multiple simultaneous requests
- **Resource Cleanup**: No memory leaks or resource exhaustion

### New Architecture Test Implementation

```elixir
defmodule AshTypescript.Rpc.V2.PipelineTest do
  use ExUnit.Case
  
  describe "new architecture - strict mode only" do
    test "fails fast on invalid fields" do
      # Test that unknown fields immediately error
      assert_raise ArgumentError, ~r/Unknown field 'invalidField'/, fn ->
        AshTypescript.Rpc.V2.parse_fields(["invalidField"], Todo, :camel_case)
      end
    end
    
    test "performance improvement over baseline" do
      large_field_list = generate_large_field_list(1000)
      
      {new_time, _} = :timer.tc(fn ->
        AshTypescript.Rpc.V2.parse_fields(large_field_list, Todo, :camel_case)
      end)
      
      # Require 50% improvement
      assert new_time < baseline_time() * 0.5
    end
    
    test "clean error messages for all failure modes" do
      # Test comprehensive error handling
      cases = [
        {"unknown_field", ~r/Unknown field/},
        {%{"malformed" => "structure"}, ~r/Invalid field format/},
        {[], ~r/Empty field list/}
      ]
      
      for {invalid_input, error_pattern} <- cases do
        assert_raise ArgumentError, error_pattern, fn ->
          AshTypescript.Rpc.V2.parse_fields(invalid_input, Todo, :camel_case)
        end
      end
    end
    
    test "memory efficiency - single pass processing" do
      # Verify no unnecessary intermediate data structures
      memory_before = :erlang.memory(:total)
      
      _result = AshTypescript.Rpc.V2.parse_fields(complex_field_list(), Todo, :camel_case)
      
      memory_after = :erlang.memory(:total)
      memory_used = memory_after - memory_before
      
      # Should use significantly less memory than current implementation
      assert memory_used < baseline_memory() * 0.7
    end
  end
end
```

## Risk Mitigation

### Implementation Risks (New Architecture Only)

1. **Implementation Errors**: New code could have bugs or edge cases
   - **Mitigation**: Comprehensive test coverage, property-based testing, stress testing

2. **Performance Issues**: Optimizations could have unintended consequences
   - **Mitigation**: Continuous benchmarking, performance requirements as tests

3. **Field Processing Errors**: Incorrect handling of complex field types
   - **Mitigation**: Exhaustive testing of all field type combinations

### Deployment Strategy

1. **Complete Replacement**: Remove old implementation entirely
2. **Extensive Testing**: 100% test coverage before deployment
3. **Performance Validation**: All performance benchmarks must pass
4. **Monitoring**: Comprehensive telemetry for the new implementation

## Success Metrics

### New Architecture Requirements
- [ ] 100% test coverage for new implementation
- [ ] Zero field processing errors in comprehensive test suite
- [ ] All field types supported with new architecture

### Performance Requirements (Non-Negotiable)
- [ ] Memory usage 30%+ better than baseline
- [ ] Processing latency 50%+ better than baseline
- [ ] Zero memory leaks under stress testing
- [ ] Single-pass processing for all operations

### Quality Requirements
- [ ] All static analysis checks pass
- [ ] Clean, self-documenting code
- [ ] Zero tolerance for technical debt
- [ ] Fail-fast error handling throughout

## Timeline Summary

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1 | Week 1 | Complete RPC pipeline rewrite, aggressive validation |
| Phase 2 | Week 2 | Advanced field types, performance optimization |
| Phase 3 | Week 3 | Comprehensive testing, stress validation |
| Phase 4 | Week 4 | Production hardening, monitoring |
| Phase 5 | Week 5 | Legacy cleanup, future-proofing |

**Total Duration**: 5 weeks
**Approach**: Complete replacement, no backwards compatibility

## Conclusion

The AshTypescript RPC refactoring represents a **complete architectural replacement** focused on performance, reliability, and maintainability. While the current implementation has the right foundation, this refactoring will build a clean, optimized system from the ground up.

### Key Principles

1. **No Backwards Compatibility**: Complete replacement of existing implementation
2. **Performance-First**: 50%+ improvement required across all metrics
3. **Fail-Fast Architecture**: Zero tolerance for invalid requests
4. **Clean Implementation**: Self-documenting, maintainable code
5. **Production-Ready**: Comprehensive testing, monitoring, error handling

The result will be a **next-generation RPC processing pipeline** that serves as a foundation for future AshTypescript development.