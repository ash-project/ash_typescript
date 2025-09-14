# AI Documentation Maintenance Guide

## Quick Reference for Documentation Updates

### Pre-Update Checklist
1. **Read [docs/ai-index.md](ai-index.md)** - Understand current structure and find related content
2. **Check dependencies** - Identify files that reference content you're updating
3. **Plan updates** - Use TodoWrite to track cross-references and index updates

### Content Standards
- **Focus on current patterns** - No historical references or announcements
- **Actionable guidance** - Practical workflows and command examples
- **Consistent terminology** - Follow existing documentation patterns
- **AI-optimized** - Information needed for efficient task completion

### Prohibited Content
- ❌ Announcement language ("This is new", "Changed at...")
- ❌ Theoretical information without practical application
- ❌ Detailed maintenance processes (keep maintenance guidance minimal)

## Documentation Types & Update Guidelines

| Type | Purpose | Key Requirements |
|------|---------|-----------------|
| **Implementation Guides** | Core system understanding | Current patterns, anti-patterns, workflows |
| **Troubleshooting** | Error resolution | Symptoms, causes, solutions, Tidewave debugging |
| **Quick References** | Rapid task completion | Commands, patterns, file locations |
| **Index & Navigation** | Efficient documentation discovery | Task-to-doc mappings, file organization |

## README Updates (Public-Facing)

**Target Audience**: End-users evaluating or using AshTypescript

**Essential Structure**:
- Value proposition (what/why)
- Quick start (installation, basic usage)
- Core features overview
- Links to comprehensive documentation

**Keep Concise**: Focus on user value, not internal architecture

## Usage Rules (Dependency Context)

**Target Audience**: AI assistants working on projects using AshTypescript as dependency

**Focus Areas**:
- Essential usage patterns
- Common gotchas and constraints
- Integration best practices
- Quick troubleshooting

**Exclude**: Internal architecture, development workflows, comprehensive API docs

## Update Workflow

1. **Plan** - TodoWrite task list with dependencies
2. **Update** - Make changes following content standards
3. **Cross-reference** - Update ai-index.md if structure changes
4. **Changelog** - Add entry for significant changes
5. **Validate** - Check links and references work correctly

---
**Purpose**: Minimal maintenance guidance for AI assistant documentation updates. Keep this file concise.