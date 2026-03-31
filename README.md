# breather

**Stop AI brain fry.** Automatic wellness monitoring for Claude Code.

---

AI coding tools make you a 100x developer, great! AND make it 100x harder to stop. HBR calls it ["AI brain fry"](https://hbr.org/2026/03/when-using-ai-leads-to-brain-fry): the mental fog, headaches, and decision fatigue from nonstop AI-assisted development. UC Berkeley [found](https://techcrunch.com/2026/02/09/the-first-signs-of-burnout-are-coming-from-the-people-who-embrace-ai-the-most/) the developers burning out first are the power users, not because anyone pressured them, but because they couldn't stop doing more.

Sound familiar? Breather is the brake pedal your AI coding setup is missing.

## How it works

Breather runs **automatically**, no discipline required. That's the point. If you had the discipline to take breaks, you wouldn't need this.

### Always on (zero effort)

| Feature | What it does |
|---------|-------------|
| **Session timer** | Color-coded status line: green < 50 min, yellow 50-90 min, red 90+ min. Always visible. |
| **Prompt tracking** | Counts prompts and session duration in the background |
| **Smart nudges** | Weaves break suggestions into Claude's responses at 25/50/90 min thresholds -- not a popup, just a natural mention |
| **Velocity detection** | Flags rapid-fire prompting (5+ prompts/min) as a sign of reactive coding, not deliberate work |
| **Yesterday awareness** | Checks if your previous sessions were marathons and adjusts accordingly |
| **Session logging** | Logs every session to JSONL so you can see your patterns over time |

### When you're ready to stop (or stretch)

| Command | What it does |
|---------|-------------|
| `/breather:stretch` | Quick break. No context saving, no ceremony. Just resets the timer partially (+10 min runway) and lets you stretch. |
| `/breather:pause` | Full break. Saves your complete context -- what you're doing, where you left off, what's next. Suggests a break duration. Fully resets the fatigue clock. |
| `/breather:back` | Restores your context instantly. No ramp-up time. Just: "Welcome back. You were working on X. Next step is Y." Archives the snapshot so you don't get stale context. |
| `/breather:checkin` | On-demand session status. Honest numbers, no guilt. |
| `/breather:reflect` | End-of-session summary: what you shipped, open threads, weekly trends. |

### What happens at session start

When you start a new Claude Code session, Breather:
1. Initializes session tracking (timer, prompt count, break counters)
2. Checks yesterday's session history for marathon patterns
3. Casually asks what your focus is for this session (sets intention without being formal)

None of this is announced. It just happens.

## The key insight

> The fear of losing context is what keeps developers from taking breaks.

If resuming costs 20 minutes of "where was I?", you'll skip the break. If `/breather:back` gets you back in 5 seconds, breaks are free. That's the lever.

## Two types of breaks

Not all breaks are equal. Breather tracks them differently:

| Type | Command | What it does | Fatigue reset |
|------|---------|-------------|---------------|
| **Stretch** | `/breather:stretch` | Eyes off screen, grab water, stand up | Partial -- adds 10 min to your runway |
| **Full break** | `/breather:pause` | Actually step away, context saved | Full reset of fatigue clock |

A stretch buys you time. A full break resets the clock. Both count toward your session stats.

## Nudge thresholds

Breather checks every prompt but won't spam you -- minimum 10 minutes between nudges.

| Time since last break | What happens |
|----------------------|-------------|
| **25 min** | Micro-break suggestion (20-20-20 rule: look at something 20 feet away for 20 seconds) |
| **50 min** | Mentions the time naturally, suggests a stretch |
| **90 min** | Directly suggests a break with `/breather:pause` |
| **5+ prompts/min** | Flags reactive mode -- "We're moving fast, want to make sure we're heading the right direction?" |

## Install

```bash
claude plugin add jessedegans-plugins/breather
```

Or from the marketplace repo:

```json
{
  "plugins": ["jessedegans-plugins/breather"]
}
```

## State and storage

All state lives in `$CLAUDE_PLUGIN_DATA` or `~/.local/share/breather/`:

| File | Purpose |
|------|---------|
| `current-session.json` | Active session state (timer, prompt count, breaks) |
| `session-history.jsonl` | All past sessions (duration, breaks, date) |
| `last-context.md` | Context snapshot from last `/breather:pause` |
| `last-reflection.md` | Summary from last `/breather:reflect` |

## Design philosophy

1. **Passive over active.** A color-coded timer you can always see beats a popup you dismiss.
2. **Reduce the cost of stopping**, not the reward of continuing.
3. **Evidence-based.** Thresholds from cognitive load research, not vibes.
4. **Never preachy.** Facts, suggestion, move on.

## The research behind it

This isn't wellness theater. Every threshold is backed by research:

| Finding | Source |
|---------|--------|
| "AI brain fry" -- AI oversight predicts 12% more mental fatigue | [HBR/BCG, 2026](https://hbr.org/2026/03/when-using-ai-leads-to-brain-fry) |
| Power users burn out first -- not from pressure, but from not stopping | [TechCrunch/UC Berkeley, 2026](https://techcrunch.com/2026/02/09/the-first-signs-of-burnout-are-coming-from-the-people-who-embrace-ai-the-most/) |
| 96% of frequent AI users work evenings/weekends monthly | [Scientific American](https://www.scientificamerican.com/article/why-developers-using-ai-are-working-longer-hours/) |
| Devs were 19% slower with AI but thought they were 20% faster | [METR study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) |
| 23 minutes to regain focus after an interruption | [Gloria Mark, UC Irvine](https://ics.uci.edu/~gmark/chi08-mark.pdf) |
| At 5 concurrent projects, 80% of time lost to switching | [Carnegie Mellon SEI](https://insights.sei.cmu.edu/blog/resource-allocation/) |
| Error rates spike after 2h of continuous deep work | Cognitive load research (Sweller, 1988) |

## Roadmap

Planned but not yet implemented:

- **Configurable thresholds** -- adjust nudge timing, status line colors via plugin settings
- **Session history viewer** -- `/breather:history` to see your patterns
- **Weekly wellness report** -- `/breather:weekly` for trend analysis
- **Nudge enforcement** -- Stop hook to verify Claude actually delivers nudges (currently Claude can rationalize skipping them)
- **Focus mode** -- temporarily disable nudges for deep work sprints with a hard time limit

## Why "breather"?

Because "take a breather" is what you'd say to a colleague who's been grinding for 4 hours straight. Not a lecture. Not a wellness app notification. Just a nudge from someone who notices.

## License

MIT
