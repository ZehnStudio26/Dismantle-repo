#!/bin/bash
# roblox-skill-router — Claude Code PreToolUse hook (Studio script-editing tools)
#
# 目的: Claude が Luau を書く直前に、関連する RbxDox リファレンスカードを機械的に
# 提示する。CLAUDE.md の「スキルを使え」はモデルへのお願いにすぎず、実際に忘れる
# （2026-08-17 のセッションで実証済み）。この hook は忘れることが構造的に不可能にする。
#
# WHY A REMINDER AND NOT A BLOCK:
#   danger-guard.sh blocks irreversible operations (exit 2). This hook must NOT block —
#   a gate on "did you read a card" would fire on every edit, be trivially satisfiable,
#   and train the model to route around it. Instead it returns CONTEXT (exit 0 + stdout),
#   which Claude Code surfaces to the model before the tool runs. The reminder arrives
#   at the only moment it matters: immediately before Luau is written.
#
# HOW IT DECIDES WHICH CARD:
#   Greps the tool-call payload for domain keywords and emits the matching card paths
#   from the skill's own routing table. Keyword -> card mapping mirrors SKILL.md so the
#   two cannot drift silently.
#
# 誤検知は無害（ただの提案テキスト）。exit 0 のみ。ツールを止めることは絶対にない。

INPUT="$(cat)"

CARDS="$HOME/.claude/skills/roblox-reference/RbxDox"

# Skill not installed on this machine -> stay silent rather than emit dead paths.
[ -d "$CARDS" ] || exit 0

# Report a Windows-style path. $HOME renders as /c/Users/... under Git Bash, which the
# Read tool cannot open; convert so the emitted paths are directly usable.
CARDS_DISPLAY="$(printf '%s' "$CARDS" | sed -E 's#^/([a-zA-Z])/#\U\1:/#')"

m() { printf '%s' "$INPUT" | grep -qiE "$1"; }

HITS=""
add() { HITS="$HITS  - RbxDox/$1  ($2)
"; }

# --- domain detection (mirrors SKILL.md's routing table) --------------------
m 'ParticleEmitter|\bBeam\b|\bTrail\b|EmitCount|ColorSequence|NumberSequence|LightEmission' \
  && add "vfx.md" "particles / beams / trails"
m 'Humanoid|TakeDamage|\.Died|MaxHealth|HipHeight|RigType' \
  && add "characters.md" "humanoid / rig behaviour"
m 'GetPartBounds|Raycast|OverlapParams|RaycastParams|Shapecast|FilterDescendantsInstances' \
  && add "raycasting.md" "hitboxes / spatial queries"
m 'CollisionGroup|CanCollide|CanQuery|CanTouch' \
  && add "collisions.md" "collision groups / query flags"
m 'AnimationTrack|LoadAnimation|GetMarkerReached|KeyframeSequence|AdjustSpeed' \
  && add "tweens-animation.md" "animation tracks / markers"
m 'CFrame|Vector3|ToOrientation|ToEulerAngles|PivotTo|LookVector' \
  && add "cframes-vectors.md" "CFrame / vector math"
m 'CollectionService|AddTag|HasTag|GetTagged' \
  && add "tags.md" "tag-driven setup"
m 'GetAttribute|SetAttribute' \
  && add "attributes.md" "designer-tunable attributes"
m 'RemoteEvent|OnServerEvent|FireClient|FireServer|ByteNet|sendToAll' \
  && add "security.md" "client->server trust boundary"
m 'DataStore|UpdateAsync|SetAsync|ProfileService' \
  && add "datastores.md" "persistence"
m 'Damage|Knockback|combo|\bBlock\b|\bStun\b' \
  && add "combat.md" "damage / combos / knockback"
m 'Heartbeat|RenderStepped|task\.spawn|task\.delay|task\.wait' \
  && add "task-scheduling.md" "scheduling / per-frame work"
m 'PathfindingService|MoveTo|:Move\(|aggro|patrol' \
  && add "npcs.md" "NPC / enemy behaviour"
# NOTE: no bare `Frame\.` here — it matched OverlapParams/RaycastParams and fired
# ui-system.md on every hitbox edit. Anchor on unambiguous UI-only identifiers.
m 'ScreenGui|TextLabel|TextButton|UDim2|ImageLabel|ImageButton|ScrollingFrame' \
  && add "ui-system.md" "UI"
m 'Instance\.new.*Sound|SoundId|PlayOnRemove' \
  && add "sound.md" "audio"
m 'Debris|:Destroy\(\)|Parent = nil' \
  && add "workspace-hierarchy.md" "instance lifecycle / Effects folder"

[ -z "$HITS" ] && exit 0

cat <<EOF
[roblox-skill-router] This edit touches an area covered by the roblox-reference skill.

Read the relevant card(s) BEFORE writing, unless you have already read them
this session:

$HITS
Cards are at: $CARDS_DISPLAY/
They are reference, not authority — where a card and this project's CLAUDE.md
disagree, CLAUDE.md wins (hard rules: no hardcoded values, no runtime UI,
server-authoritative, --!strict).
EOF

exit 0
