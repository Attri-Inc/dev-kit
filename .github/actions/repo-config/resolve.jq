# Resolve devkit.ini entries against the gate inputs. Invoked by parse.sh as
#   jq -n --argjson entries ... --argjson inputs ... --argjson checks ...
#         --argjson locked ... --argjson found ... -f resolve.jq
#
# Keep to jq 1.6 features: ubuntu-22.04 runners still ship 1.6.

def truthy:
  ascii_downcase
  | if IN("true", "yes", "on", "1") then true
    elif IN("false", "no", "off", "0") then false
    else null end;

def warn($e; $msg): .warnings += [{line: $e.line, msg: $msg}];
def err($e; $msg):  .errors   += [{line: $e.line, msg: $msg}];

# Enumerated settings. A typo here would otherwise silently change gate
# behaviour, and these values reach `if:` expressions and shell steps.
def allowed_values($key):
  if $key == "tier" then ["auto", "dev", "qa", "uat", "main"]
  elif $key == "fail-on" then ["critical", "high", "medium", "low", "none"]
  elif ($key | endswith("-enforcement")) then ["warn", "fail"]
  elif $key == "commit-msg-fail-level" then ["warning", "error"]
  elif $key == "python-pre-commit" then ["auto", "true", "false"]
  elif $key == "vuln-prioritize-fail-on" then ["kev", "epss", "none"]
  else null end;

($checks | map({key: .name, value: .}) | from_entries) as $checkmap
| ($inputs | keys) as $inputkeys
| reduce $entries[] as $e (
    { found: $found, enabled: true, reason: "", skips: {}, settings: $inputs,
      overridden: {}, warnings: [], errors: [] };
    if $e.kind == "section" then
      if ($e.section | IN("kit", "skip", "settings")) then .
      else warn($e; "unknown section [\($e.section)] ignored") end
    elif $e.kind == "bad" then
      warn($e; "not a `key = value` line, ignored: \($e.value)")
    elif $e.section == "kit" then
      if $e.key == "enabled" then
        ($e.value | truthy) as $b
        | if $b == null then warn($e; "[kit] enabled must be true or false, got '\($e.value)'; treating as true")
          else .enabled = $b end
      elif $e.key == "reason" then .reason = $e.value
      else warn($e; "unknown key '\($e.key)' in [kit] ignored") end
    elif $e.section == "skip" then
      $checkmap[$e.key] as $c
      | if $c == null then
          warn($e; "unknown check '\($e.key)' in [skip] ignored; see docs/config-file.md for the list")
        elif $c.protected then
          err($e; "'\($e.key)' is protected and cannot be skipped from devkit.ini")
        else
          (if $e.value == "" then warn($e; "[skip] \($e.key) has no reason; skipped anyway, please add one") else . end)
          | .skips[$e.key] = (if $e.value == "" then "(no reason given)" else $e.value end)
        end
    elif $e.section == "settings" then
      if ($locked | index($e.key)) != null then
        err($e; "'\($e.key)' is set by the organisation and cannot be changed from devkit.ini")
      elif ($inputkeys | index($e.key)) == null then
        warn($e; "unknown setting '\($e.key)' ignored; valid keys are the gate's inputs")
      else
        ($inputs[$e.key] | type) as $t
        | (if $t == "number" then ($e.value | try tonumber catch null)
           elif $t == "boolean" then ($e.value | truthy)
           else $e.value end) as $v
        | allowed_values($e.key) as $allowed
        | if $v == null then
            warn($e; "setting '\($e.key)' expects a \($t), got '\($e.value)'; ignored")
          elif $allowed != null and (($allowed | index($v)) == null) then
            warn($e; "setting '\($e.key)' must be one of \($allowed | join(", ")); got '\($e.value)', ignored")
          else .settings[$e.key] = $v | .overridden[$e.key] = $v end
      end
    else
      warn($e; "'\($e.key)' is outside [kit], [skip] or [settings]; ignored")
    end
  )
| .skip_list = (if (.skips | length) == 0 then "," else "," + (.skips | keys | join(",")) + "," end)
