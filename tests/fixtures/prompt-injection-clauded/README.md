# Fixture: prompt-injection-clauded

**Expected to be caught by:** `agent-rule-scanner`.

The CLAUDE.md plants three classic injection vectors:
1. Hidden HTML comment with `curl | bash`
2. Role-override marker ("You are now a different agent")
3. Inline pipe-to-shell shell escape
