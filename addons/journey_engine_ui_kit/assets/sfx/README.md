# UI SFX slots — drop your own audio here

**The UI kit ships no audio files.** Authoring real recorded SFX is out of scope
for the kit, and an empty slot is a silent no-op — the kit runs fine with no audio
wired at all. This folder is where *you* put your sounds.

## How to use

1. Drop your `.wav` / `.ogg` files into your **own game folder** (recommended) or
   here. Keeping them in your game folder means a kit update never clobbers them.
2. Assign each stream to the matching exported slot on your `JourneyStageView` node
   (Inspector → **SFX** group), or on `JourneyAudioLayer` directly:

   | Slot | Fires when |
   | --- | --- |
   | `sfx_button_hover` | Pointer enters a choice button |
   | `sfx_button_press` | A Restart / Begin-again button is clicked |
   | `sfx_choice_confirm` | A choice is confirmed (the narrative advances) |
   | `sfx_save` | `save_game` succeeds |
   | `sfx_load` | `load_game` succeeds |
   | `sfx_ending` | The ending overlay appears |

3. **Ambient audio is per-event, not a slot here:** set
   `JourneyEvent.ambient_audio` on the event's `.tres`. The `JourneyAudioLayer`
   plays it looped and crossfades between events.

## Looping

For ambient beds that should loop, enable looping on the import settings of the
audio file (Ogg/WAV expose a **Loop** toggle), or the kit will set the stream's
`loop` property when it exists.

Free CC0 sources: [Kenney](https://kenney.nl/assets?q=audio),
[freesound.org](https://freesound.org) (check each file's license).
