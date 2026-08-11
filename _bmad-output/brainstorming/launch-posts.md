# cc-hdrm Launch Posts

## Post 1: "5h Window Myth" — Standalone Value Post

**Goal:** Establish authority, drive organic repo traffic
**Platform:** r/ClaudeAI
**Suggested date:** Tuesday 2026-03-03, 4:00 PM CET (10:00 AM ET)

### Title (pick one)

A: The 5-hour window doesn't eat your weekly allowance — here's how it actually works

B: Stop batching to "save windows" — that's not how Claude's weekly limit works

### Body

There's a misconception going around that every time you start a Claude session, you "spend" a 5-hour window from your weekly pool — so doing three short check-ins in a day burns three windows worth of weekly quota, even if you barely used them.

That's not how it works.

The 5-hour window is a burst-rate cap. It limits how many messages you can send in a rolling 5-hour period. The weekly ceiling is separate — it tracks your actual cumulative consumption, not how many windows you opened.

If you open a session, send two messages, and walk away — you used two messages worth of weekly quota. Not a full window's worth. The window just resets after 5 hours regardless.

So the "batch everything into one long session to save windows" advice is solving the wrong problem. Batching is great for focus, but it doesn't conserve weekly quota. Short check-ins don't waste anything.

I know this because I built [cc-hdrm](https://github.com/rajish/cc-hdrm), a menu bar app that polls the actual usage API every 30 seconds and shows your remaining headroom in the macOS menu bar. The data is unambiguous — weekly usage goes up by what you consume, not by how many sessions you start.

---

## Post 2: "5h Window Myth" — LinkedIn Version

**Goal:** Reach professional developer network, drive repo traffic
**Platform:** LinkedIn
**Suggested date:** Wednesday 2026-03-04, 4:00 PM CET (10:00 AM ET)
**Note:** Post one day after Reddit to avoid splitting attention. If Reddit post gains traction, mention it ("this blew up on Reddit yesterday").

### Body

There's a myth spreading about Claude's usage limits that's costing developers unnecessary stress.

The claim: every time you start a Claude session, you "spend" a 5-hour window from your weekly pool. Three short check-ins = three windows burned, even if you barely typed anything.

That's wrong.

I know because I built a tool that reads the actual usage API. The data is clear:

- The 5-hour window is a burst-rate cap (max messages per rolling period)
- The weekly ceiling tracks actual consumption
- They're independent

Send two messages and walk away? You used two messages of weekly quota. Not a full window.

The "batch everything into marathon sessions" advice going around isn't wrong for focus — but it doesn't save weekly quota. Short check-ins cost exactly what you use in them.

I got tired of guessing where I stood, so I built cc-hdrm — a macOS menu bar app that shows your remaining Claude headroom at a glance. Free, open source, polls every 30 seconds, zero tokens spent.

https://github.com/rajish/cc-hdrm

---

## Post 3: Big Bang Launch — Show HN

**Goal:** GitHub trending via star velocity burst
**Platform:** Hacker News (Show HN)
**Suggested date:** Tuesday 2026-03-11, 4:00 PM CET (10:00 AM ET)
**Prerequisite:** README overhaul done. Before/after screenshots ready. 2-3 friends ready to upvote and comment within first 30 minutes.
**Note:** One week after the myth posts. By then the Reddit/LinkedIn posts may have driven some initial stars past the "zero social proof" threshold.

### Title

Show HN: I kept getting cut off mid-task by Claude, so I built a usage monitor

### First comment

I'm on Claude Max and use Claude Code all day. The 5-hour rate limit kept catching me mid-build — no warning, just "usage limit reached" right when I was deep in a refactor.

The only ways to check are /usage (costs tokens, breaks flow), the web dashboard (full context switch), or a browser extension (useless for CLI users). None of them passively inform you.

So I built cc-hdrm — a macOS menu bar app that polls Anthropic's usage API every 30 seconds and shows your remaining headroom at a glance. Color-coded percentage in the menu bar, ring gauges and reset countdowns in the popover, threshold notifications before you hit the wall, and an analytics window with historical charts.

Pure Swift/SwiftUI, zero dependencies, zero tokens spent. OAuth sign-in via your browser, credentials in Keychain, no telemetry.

brew install rajish/tap/cc-hdrm

https://github.com/rajish/cc-hdrm

---

## Post 4: Big Bang Launch — r/ClaudeAI

**Goal:** Reddit engagement + repo traffic, coordinated with HN
**Platform:** r/ClaudeAI
**Suggested date:** Tuesday 2026-03-11, 4:30 PM CET (10:30 AM ET)
**Note:** Post 30 minutes after HN so you're not splitting your own attention. Different title and framing from the myth post — this one is a "look what I built" post.

### Title

I got tired of getting surprise-throttled, so I built a free menu bar app that shows your Claude headroom

### Body

If you use Claude Code and have been hit by rate limits mid-session, this might help.

cc-hdrm sits in your macOS menu bar and shows your remaining headroom percentage — color-coded from green to red, with burn rate arrows so you can see how fast you're consuming it. Click for ring gauges, reset countdowns, and a 24-hour sparkline. Open the analytics window for historical charts and subscription value breakdown.

It polls the usage API every 30 seconds. Zero tokens spent, no telemetry, fully open source.

[demo GIF or before/after screenshot here]

`brew install rajish/tap/cc-hdrm`

https://github.com/rajish/cc-hdrm

---

## Timing Summary

| Date | Time (CET) | Platform | Post |
|------|-----------|----------|------|
| Tue 2026-03-03 | 16:00 | r/ClaudeAI | 5h window myth |
| Wed 2026-03-04 | 16:00 | LinkedIn | 5h window myth |
| Tue 2026-03-11 | 16:00 | Hacker News | Big bang launch |
| Tue 2026-03-11 | 16:30 | r/ClaudeAI | Big bang launch |

## Pre-Launch Checklist

- [ ] README overhaul merged to master
- [ ] Before/after screenshot pair taken
- [ ] DM sent to SoloSwiftCrafter
- [ ] 2-3 friends briefed and ready for launch day upvotes/comments
- [ ] Demo GIF or screenshot prepared for Reddit launch post
- [ ] Newsletter/YouTuber outreach list identified (send on launch day or day after)
