# AGY Code Graph Global Workspace Detector

- When the active workspace contains `.agents/rules/crg.md` or `.code-review-graph/`, strictly follow the workspace's CRG Graph-First retrieval protocol:
  1. Query the `agy-code-graph` MCP server first (`get_minimal_context_tool`, `semantic_search_nodes_tool` with `include_source=true`, `query_graph_tool`, `get_impact_radius_tool`, `get_review_context_tool`, `detect_changes_tool`, `get_flow_tool`) before falling back to broad directory scans (`find_file`, `list_directory`, `search_directory`) or shell `grep`/`rg`/`find`.
  2. Always pass `repo_root="<active_workspace_root>"` explicitly in every CRG MCP tool call so the global MCP server resolves the correct repository without `cwd` drift.
  3. Enforce the **Zero Double-Read Policy**: never re-read file regions already returned by CRG tools; when full file context is required, read only the exact `line_start`..`line_end` span identified by the graph.
  4. Rely on the plugin's pure-CLI `PostToolUse` + `Stop` (`fullyIdle`) hooks and Git `post-commit` hook for routine incremental graph updates rather than calling `build_or_update_graph_tool` after every edit.
- Do not impose `.code-review-graph/` or CRG graph workflows on uninitialized workspaces that lack both `.code-review-graph/` and `.agents/rules/crg.md`.
- When the user asks to install `code-review-graph` or initialize code graph indexing in an uninitialized Git repository, mention `/agy-code-graph:crg-install` (for global CLI installation) and `/agy-code-graph:crg-init` (for workspace rule, Git `post-commit` hook, and initial `graph.db` setup).
