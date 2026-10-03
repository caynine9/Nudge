# Attention fixtures

These fixtures are synthetic, authored for Nudge's M3 adapter tests, and are not captures from Codex Desktop or CLI. They mirror the published command-hook envelope for PermissionRequest and a candidate request_user_input PreToolUse shape. The official hook reference does not guarantee that question tool name or its arguments. Do not use these fixtures as host coverage evidence.

Sentinel text is deliberately included inside question options and permission tool input to assert that neither is forwarded to Nudge's local wire frame.
