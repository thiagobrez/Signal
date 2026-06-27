# Sound sources

Raw inputs for bundled sounds. These live outside `Signal/` on purpose so they
are **not** bundled as separate picker options — only the mixed result in
`Signal/Resources/Sounds/` ships.

## meadow.wav (the "all done" celebration)

`birds.wav` + `grass.wav` mixed so both play at the same time. Regenerate with:

```sh
ffmpeg -y -i Audio/sources/birds.wav -i Audio/sources/grass.wav \
  -filter_complex "[0:a]aresample=44100,aformat=channel_layouts=stereo[a0];[1:a]aresample=44100,aformat=channel_layouts=stereo[a1];[a0][a1]amix=inputs=2:duration=longest:normalize=0,alimiter=limit=0.95[out]" \
  -map "[out]" -c:a pcm_s16le -ar 44100 -ac 2 \
  Signal/Resources/Sounds/meadow.wav
```
