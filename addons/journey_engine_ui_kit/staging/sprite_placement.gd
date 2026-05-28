extends Resource
class_name JourneySpritePlacement

## One foreground sprite and how to stage it: which texture, where it sits, how it
## enters, and how tall it is. Pure presentation/direction data — it lives in the kit
## (a JourneyStageEntry), never in the core JourneyEvent.

## Where the sprite anchors horizontally. Vertically it sits on the bottom edge (a
## standing figure), nudged by `offset`.
enum Anchor { CENTER, LEFT, RIGHT }

## How the sprite animates in when its event is entered.
enum Enter { FADE, SLIDE_UP, SLIDE_SIDE }

@export var texture: Texture2D
@export var anchor: Anchor = Anchor.CENTER
## Pixel nudge from the anchored resting position (x right, y down).
@export var offset: Vector2 = Vector2.ZERO
@export var enter: Enter = Enter.SLIDE_UP
@export var flip_h: bool = false
## Sprite height as a fraction of the view height (1.0 = full height).
@export_range(0.1, 1.0, 0.01) var height_ratio: float = 0.7
