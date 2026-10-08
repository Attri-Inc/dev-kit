# Fixture: slopsquat-pkg

**Expected to be caught by:** `import-existence`.

`requirements.txt` and `package.json` each include one real package + one obviously-hallucinated package name. The action should resolve the real ones and fail on the fake ones.
