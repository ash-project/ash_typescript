# AI Assistant Documentation Update Guide

## Overview

When updating AI assistant documentation, maintain established patterns and focus on creating a practical reference corpus. Documentation should provide AI assistants with the context and knowledge needed to complete tasks efficiently and correctly.

## Pre-Update Analysis (MANDATORY)

Before making any AI documentation changes, you MUST:

1. **Read the AI Index First**: Start with `docs/ai-index.md` to understand current documentation structure and find related content
2. **Identify Documentation Type**: Determine if you're updating:
   - AI implementation guides (setup, patterns, workflows)
   - AI troubleshooting documentation (error patterns, debugging guides)
   - AI quick reference materials (command references, critical reminders)
   - AI-specific architectural documentation (context optimization, task mapping)
3. **Check Dependencies**: Identify other AI documentation files that reference the content you're updating
4. **Assess Impact**: Determine if changes will affect the AI index, task-to-documentation mappings, or established workflows

## AI Documentation Update Workflow

### 1. Planning Phase

Use TodoWrite to create an update plan with these steps:
- Read `docs/ai-index.md` to understand current documentation structure
- Identify specific AI documentation files to update/create/remove
- Check cross-references and dependencies
- Plan updates to maintain workflow consistency
- Update AI index task mappings if needed
- Plan changelog entry for significant changes

### 2. Content Standards

**Focus Areas:**
- Current state of the system and correct usage patterns
- Code patterns that should be used
- Anti-patterns that should be avoided
- Workflows for different types of tasks
- Context needed for efficient task completion

**Content Requirements:**
- Follow existing documentation patterns (structure, tone, formatting)
- Use consistent terminology and command examples
- Maintain technical detail appropriate for AI assistants
- Include practical, actionable information
- Remove any change tracking or historical references

**Prohibited Content:**
- ❌ "This is a new feature" or similar announcement language
- ❌ Timestamp announcements ("Changed at...", "Updated on...")
- ❌ "NOW UPDATED" or similar change tracking language
- ❌ Historical change references or version comparisons
- ❌ Meta-commentary about features being new or old

### 3. File Guidelines

**For All Documentation Updates:**
- Document the current state only
- Focus on practical usage patterns
- Include command examples that work with current codebase
- Maintain consistent file structure and organization
- Ensure all internal links remain functional

**For New Documentation:**
- Place in `docs/` directory following established categorization
- Use consistent naming conventions (kebab-case, descriptive)
- Include proper documentation headers and structure
- Immediately update `docs/ai-index.md` with new file reference

**For Removing Documentation:**
- Mark as deprecated first with clear migration path
- Update all references to point to replacement documentation
- Remove from `docs/ai-index.md` and update task mappings
- Delete only after confirming no dependencies exist

### 4. AI Index Maintenance (CRITICAL)

Whenever you update AI documentation, update `docs/ai-index.md`:
- Add new documentation files to appropriate task categories
- Update file descriptions and context window size references
- Maintain task-to-documentation mapping
- Update context window optimization notes
- Keep "Quick Navigation" section current

### 5. Changelog Maintenance (REQUIRED)

For significant changes, update `docs/ai-changelog.md`:
- Add entry with current date
- Describe what was changed and why
- List affected files
- Explain impact on future development
- Include key insights or patterns discovered
- Follow the established entry format

### 6. Quality Assurance

**Content Quality:**
- Information accurate for current codebase
- Command examples tested and functional
- Technical depth appropriate for AI implementation
- Consistent tone and style
- TodoWrite examples functional

**Structure Quality:**
- Follows established formatting patterns
- Headers and organization match similar documents
- Code blocks use consistent syntax highlighting
- All links and references functional

**Integration Quality:**
- AI index updated with content changes
- Cross-references updated throughout documentation
- Task-to-documentation mappings accurate
- No broken internal links

### 7. Specialized Documentation Types

**Implementation Guides:**
- Include task-to-documentation mappings
- Reference file sizes for context window optimization
- Maintain mandatory documentation reading workflow
- Include TodoWrite examples and patterns
- Specify correct command usage (e.g., `mix test.codegen`)

**Troubleshooting Documentation:**
- Include error patterns and solutions
- Reference common workflow mistakes and corrections
- Maintain debugging patterns and approaches
- Include validation steps and quality checks

**Quick Reference Materials:**
- Optimize for quick AI assistant lookup
- Include critical workflow reminders and patterns
- Maintain consistent command reference formats
- Include safety checks and validation steps

## Validation Steps

After completing documentation updates:
1. **Test Examples**: Ensure workflow examples and commands work with current codebase
2. **Check Links**: Verify all internal links are functional
3. **Review AI Index**: Confirm `docs/ai-index.md` accurately reflects changes
4. **Update Changelog**: Add entry to `docs/ai-changelog.md` for significant changes
5. **Cross-Reference Check**: Ensure other documentation referencing changes is accurate
6. **Pattern Consistency**: Verify changes follow established patterns
7. **Context Window Check**: Ensure documentation remains optimized for AI context usage

## Error Prevention

Common mistakes to avoid:
- ❌ Creating documentation without updating AI index
- ❌ Making significant changes without updating changelog
- ❌ Changing established workflow patterns without updating related files
- ❌ Removing documentation without checking dependencies
- ❌ Adding content without considering context window impact
- ❌ Updating technical details without testing workflow examples
- ❌ Breaking existing cross-references and links
- ❌ Including change tracking or historical references