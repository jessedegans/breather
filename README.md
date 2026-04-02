# breather

**Stop AI brain fry.** Automatic break reminders for Claude Code.

---

AI coding tools make you a 100x developer, great! AND make it 100x harder to stop. HBR calls it ["AI brain fry"](https://hbr.org/2026/03/when-using-ai-leads-to-brain-fry): the mental fog, headaches, and decision fatigue from nonstop AI-assisted development. UC Berkeley [found](https://techcrunch.com/2026/02/09/the-first-signs-of-burnout-are-coming-from-the-people-who-embrace-ai-the-most/) the developers burning out first are the power users, not because anyone pressured them, but because they couldn't stop doing more.

Sound familiar? Breather is the brake pedal your AI coding setup is missing.

## How it works

After a quick one-time setup (`/breather:setup`), breather runs **automatically** -- no discipline required. That's the point. If you had the discipline to take breaks, you wouldn't need this.

### Always on (zero effort)

| Feature | What it does |
|---------|-------------|
| **Daily fatigue tracking** | Tracks total AI work time across ALL your Claude Code sessions, not just one terminal |
| **Status line** | `breather session: 45m \| today: 3h 12m \| 1 break` -- session time is info, daily total goes green/yellow/red |
| **Smart nudges** | Weaves break suggestions into Claude's responses at 25/50/90 min thresholds based on daily total |
| **Inactivity detection** | Long gaps (30+ min) between prompts are detected as breaks automatically. No commands needed. |
| **Velocity detection** | Flags rapid-fire prompting (5+ prompts/min) as a sign of reactive coding |
| **Overnight reset** | 8+ hour gap = fresh start. Yesterday's fatigue doesn't carry over. |
| **Session logging** | Logs every session to JSONL for future pattern analysis |

### When you're ready to stop (or stretch)

| Command | What it does |
|---------|-------------|
| `/breather:stretch` | Quick break. No context saving, no ceremony. Partial fatigue reset (+10 min). |
| `/breather:pause` | Full break. Saves YOUR mental context (what you were doing, where you left off, what's next). Fully resets the fatigue clock. |
| `/breather:back` | Restores your context instantly. No ramp-up time. |
| `/breather:checkin` | Session + daily stats. Honest numbers, no guilt. |
| `/breather:reflect` | End-of-session summary: what you shipped, open threads, weekly trends. |

### You don't need to remember commands

Breather detects long gaps between prompts automatically. If you step away for 45+ minutes, it counts as a break -- no commands needed.

`/breather:pause` is there for when you want the context-saving full stop (so `/breather:back` can restore exactly where you were). For shorter breaks, `/breather:stretch` is a quick one-liner.

## The key insight

> The fear of losing context is what keeps developers from taking breaks.

If resuming costs 20 minutes of "where was I?", you'll skip the break. If `/breather:back` restores YOUR mental context in 5 seconds, breaks are free. That's the lever.

## Multi-session aware

Most devs run 3-8 Claude Code terminals simultaneously. Breather tracks fatigue **globally**:

- Each session writes its own state file
- The status line and nudge system read ALL session files to compute daily totals
- A break in one window is visible in all windows
- "Taking a break" in terminal 3 resets the fatigue clock everywhere

The number that matters is your total AI work today, not how long one terminal has been open.

## Nudge thresholds

Based on **daily total since last break** across all sessions:

| Time | What happens |
|------|-------------|
| **25 min** | "Eyes off screen -- look at something 6 meters away for 20 seconds." |
| **50 min** | Mentions the time naturally, suggests `/breather:stretch` |
| **90 min** | Directly suggests `/breather:pause` with context saving |
| **5+ prompts/min** | "We're moving fast -- right direction?" |

Minimum 10 minutes between nudges. One nudge per response max.

## Install

```bash
/plugin marketplace add jessedegans/breather
/plugin install breather@breather
```

### First-time setup

After installing, run:

```
/breather:setup
```

This walks you through one-time setup: enables the status line, gives a quick tour of what breather does, and makes sure everything is working. Takes about 30 seconds. Restart Claude Code after setup.

## State and storage

All state lives in `$CLAUDE_PLUGIN_DATA` or `~/.local/share/breather/`:

| Path | Purpose |
|------|---------|
| `sessions/{id}.json` | One file per active Claude Code session |
| `history.jsonl` | All past sessions (append-only log) |
| `reflections.md` | Running log of end-of-session reflections |
| `last-context.md` | Context snapshot from last `/breather:pause` |
| `last-reflection.md` | Most recent reflection (for quick access) |

## Design philosophy

1. **Passive over active.** A color-coded timer you can always see beats a popup you dismiss.
2. **Reduce the cost of stopping**, not the reward of continuing.
3. **Evidence-based.** Thresholds from cognitive load research, not vibes.
4. **Never preachy.** Facts, suggestion, move on.
5. **Self-healing.** Every script handles missing state. Nothing crashes because a hook didn't fire.

### The nudge problem (and how we solve it)

Here's the core tension: breather tells Claude "suggest a break," but Claude is an LLM optimizing to be helpful with your question. It can rationalize skipping the nudge -- "the user seems focused, I'll just answer." The very thing that makes AI coding addictive (it always wants to keep helping) works against the break suggestion.

We solve this in three layers:

**1. Appeal to helpfulness, don't fight it.** The prompt says: "This user installed a break reminder because they know they won't stop on their own. You are their safety net. The most helpful thing you can do right now is suggest a break." This reframes the break as Claude's job, not an interruption to it.

**2. Detect when Claude ignores it.** A Stop hook fires after every response, scans for evidence that the nudge was delivered. If it wasn't, we know.

**3. Bypass to status line.** After 2 ignored nudges, stop trying to convince Claude. The status line shows yellow "take a break" where the break count normally sits. The user sees it every response, no LLM cooperation needed.

This is the hard problem in AI-native break reminders. You can't just show a popup -- the interface IS the AI, and the AI has opinions about what's helpful.

## The research behind it

This isn't vibes-based. Every threshold is backed by research:

| Finding | Source |
|---------|--------|
| "AI brain fry" -- AI oversight predicts 12% more mental fatigue | [HBR/BCG, 2026](https://hbr.org/2026/03/when-using-ai-leads-to-brain-fry) |
| Power users burn out first -- not from pressure, but from not stopping | [TechCrunch/UC Berkeley, 2026](https://techcrunch.com/2026/02/09/the-first-signs-of-burnout-are-coming-from-the-people-who-embrace-ai-the-most/) |
| 96% of frequent AI users work evenings/weekends monthly | [Scientific American](https://www.scientificamerican.com/article/why-developers-using-ai-are-working-longer-hours/) |
| Devs were 19% slower with AI but thought they were 20% faster | [METR study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) |
| Visible countdowns induce stress and degrade executive function | [Waugh et al. 2022, Acta Psychologica](https://doi.org/10.1016/j.actpsy.2022.103656) |
| 23 minutes to regain focus after an interruption | [Gloria Mark, UC Irvine](https://ics.uci.edu/~gmark/chi08-mark.pdf) |
| Error rates spike after 2h of continuous deep work | Cognitive load research (Sweller, 1988) |

## Roadmap

- **Break commitment** -- "break in 10 minutes" with gentle pre-notification and statusline reminder (no countdown -- research shows countdowns induce stress)
- **Configurable thresholds** -- adjust nudge timing, status line colors via plugin settings
- **Session history viewer** -- `/breather:history` to see your patterns
- **Weekly report** -- `/breather:weekly` for trend analysis
- **Focus mode** -- temporarily disable nudges for deep work sprints with a hard time limit

## Why "breather"?

Because "take a breather" is what you'd say to a colleague who's been grinding for 4 hours straight. Not a lecture. Not a notification you dismiss. Just a nudge from someone who notices.

## License

MIT
