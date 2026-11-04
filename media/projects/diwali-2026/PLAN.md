# Diwali 2026 greeting (4:5, 20 s, English voice)

Deliver by Fri 6 Nov 2026 so it can be posted before Diwali (Sun 8 Nov). Brief from the user: rangoli + diyas, English voice (Kokoro), 4:5, 15-20 s. Nothing about the product: this is a greeting.

## Subject inventory (things that belong to this night, not to "festive templates")
1. Amavasya: the new-moon night, the darkest of the month. Diwali is on it.
2. Rangoli drawn by hand at the doorstep, in coloured powder, with a dot grid as its guide.
3. Powder that does not draw a perfect line: grain, wobble, thicker where the hand slowed.
4. Diyas: small clay lamps, wick, oil; a row along the threshold.
5. One lamp lit from another; the first flame does not get smaller.
6. Marigold orange, turmeric yellow, vermilion, rice-flour white.
7. Warm light on a dark floor: the only light source in the frame is the flames.
8. The doorway / threshold as the stage (the rangoli faces the street).
9. A tanpura-like drone: the sound of an evening at home, not a "festive" jingle.
10. Yourider: only as the sender, at the end.

## Idea
The film starts in near-darkness (the new moon) and ends lit, with all light coming from lamps that were lit one from the next. The rangoli is drawn on the beat of the voice as a hand would draw it: dot grid first, then the lines. Line L4 is the thought of the film: a flame shares its light and loses nothing.

## Story
- Setup (0-4.5): dark floor, a thin new-moon sky edge or just darkness; the dot grid appears dot by dot (the guide a person draws first). Voice L1.
- Build (4.5-11): the rangoli is drawn stroke by stroke over the dots (powder texture), colour fills; on "one lamp" the first diya is lit (match, flame catches). L3 "the next one, from the first": the flame passes to lamp 2, then quickly along the row.
- Turn (11.4-14.3): L4. All lamps lit, light grows across the rangoli; the first flame stays the same size (show it: it does not dim).
- Silence (14.3-15.4): no voice, only drone and flames.
- End (15.4-20): "Happy Diwali" lockup, sign "from all of us at Yourider", held >= 2.5 s.

## Shots / engine
HyperFrames (HTML + GSAP), SVG for the rangoli (stroke drawing with dash offset, rough powder edge via SVG filter), CSS/SVG flames with a slow, non-repeating flicker. No stock images needed. All timing anchored to words.json.

## Sound plan
- Drone bed (synthesised tanpura-like: Sa-Pa-Sa-Sa plucks with buzz), low, from 0 s; fades in, swells slightly at L4, holds under the end.
- Match strike + flame catch on "lamp" (L2). Softer catches as each lamp is lit after "first" (L3), quieter each time.
- Real silence of the voice 14.3-15.4 (drone continues; check.py silence window applies to the voice track, see builder note).
- One small bell (synthesised, or a CC0 Openverse sound recorded in rights.md) on "Diwali" in L5.
- Nothing licensed from unknown sources. Every sound in rights.md.

## Refused defaults (for the designer to extend)
Fireworks bursts, gold glitter particles, a centred "Happy Diwali" in a script font with a sparkle, emoji diyas, lens flares, a stock photo of a woman lighting a lamp, a product pitch.
