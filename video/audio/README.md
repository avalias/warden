# Voiceover audio for the pitch deck

Drop your AI-generated narration here, one file per part:

```
part-1.mp3   # The hook
part-2.mp3   # The inversion
part-3.mp3   # The heart (the freeze)
part-4.mp3   # It's all real
part-5.mp3   # Seven layers
part-6.mp3   # Why it advances / close
```

Then open `../index.html` and press **▶ Play with audio** — each part plays its
clip and auto-advances to the next when the clip ends. With no audio present, it
falls back to the per-part `data-dur` timing so you can rehearse the pacing.

The exact narration script for each part is the on-screen caption (toggle with
**N**) and the `NARRATION` array in `index.html`.
