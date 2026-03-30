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
| **Session timer** | Color-coded status line: green < 90min, yellow < 3h, red 3h+. Always visible. |
| **Prompt tracking** | Counts prompts and session duration in the background |
| **Smart nudges** | After 2+ hours without a break, weaves awareness into Claude's responses — not a popup, just a natural mention |
| **Check-in loop** | Auto-starts a 45-minute wellness check at session start. You didn't ask for it. It just happens. |
| **Session logging** | Logs every session so you can see your patterns over time |

### When you're ready to stop

| Command | What it does |
|---------|-------------|
| `/pause` | Saves your full context — what you're doing, where you left off, what's next. Suggests a break duration based on how long you've been going. |
| `/resume` | Restores your context instantly. No ramp-up time. Just: "Welcome back. You were working on X. Next step is Y." |
| `/checkin` | On-demand session status. Honest numbers, no guilt. |
| `/reflect` | End-of-session summary: what you shipped, open threads, weekly trends. |

## The key insight

> The fear of losing context is what keeps developers from taking breaks.

If resuming costs 20 minutes of "where was I?", you'll skip the break. If `/resume` gets you back in 5 seconds, breaks are free. That's the lever.

## Install

```bash
claude --plugin /path/to/breather
```

Or add to your Claude Code settings:

```json
{
  "plugins": ["/path/to/breather"]
}
```

## Defaults

Works out of the box, no config needed:

| Setting | Default |
|---------|---------|
| Check-in loop | Every 45 minutes |
| Yellow threshold | 90 minutes |
| Red threshold | 180 minutes |
| Nudge frequency | Every 10 prompts (after threshold) |

State stored in `$CLAUDE_PLUGIN_DATA` or `~/.local/share/breather/`.

## Design philosophy

1. **Passive over active.** A color-coded timer you can always see beats a popup you dismiss.
2. **Reduce the cost of stopping**, not the reward of continuing.
3. **Evidence-based.** Thresholds from cognitive load research, not vibes.
4. **Never preachy.** Facts, suggestion, move on.

## The research behind it

This isn't wellness theater. Every threshold is backed by research:

| Finding | Source |
|---------|--------|
| "AI brain fry" — AI oversight predicts 12% more mental fatigue | [HBR/BCG, 2026](https://hbr.org/2026/03/when-using-ai-leads-to-brain-fry) |
| Power users burn out first — not from pressure, but from not stopping | [TechCrunch/UC Berkeley, 2026](https://techcrunch.com/2026/02/09/the-first-signs-of-burnout-are-coming-from-the-people-who-embrace-ai-the-most/) |
| 96% of frequent AI users work evenings/weekends monthly | [Scientific American](https://www.scientificamerican.com/article/why-developers-using-ai-are-working-longer-hours/) |
| Devs were 19% slower with AI but thought they were 20% faster | [METR study](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) |
| 23 minutes to regain focus after an interruption | [Gloria Mark, UC Irvine](https://ics.uci.edu/~gmark/chi08-mark.pdf) |
| At 5 concurrent projects, 80% of time lost to switching | [Carnegie Mellon SEI](https://insights.sei.cmu.edu/blog/resource-allocation/) |
| Error rates spike after 2h of continuous deep work | Cognitive load research (Sweller, 1988) |

## Why "breather"?

Because "take a breather" is what you'd say to a colleague who's been grinding for 4 hours straight. Not a lecture. Not a wellness app notification. Just a nudge from someone who notices.

## License

MIT
