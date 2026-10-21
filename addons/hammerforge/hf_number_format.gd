@tool
class_name HFNumberFormat
extends RefCounted
## How a length is printed wherever HammerForge shows one: the mode banner, the
## context toolbar, the size beside the cursor, the size labels on a selection
## and the Selection Info section.
##
## As many decimal places as the grid step needs, so a 0.25 snap reads 0.25 and
## not 0.3, with trailing zeros dropped, so a whole size reads 2 and not 2.00.
## Never fewer than two places: a size can be off the grid (snap off, a turned
## brush's bounds, a vertex moved by hand), and rounding it onto a whole number
## would show a size the brush does not have.

const MIN_DECIMALS := 2
const MAX_DECIMALS := 4


## The decimal places a length on a grid of [param step] needs: 2 for any step of
## a hundredth or coarser, 3 for 0.125, 4 for 0.0625 and anything finer.
static func decimals(step: float = 0.0) -> int:
	var places := MIN_DECIMALS
	if step > 0.0 and is_finite(step):
		while places < MAX_DECIMALS and not _is_whole(step * pow(10.0, places)):
			places += 1
	return places


## [param value] to the grid's precision: "2", "2.5", "0.25", "0.125".
static func number(value: float, step: float = 0.0) -> String:
	if not is_finite(value):
		return str(value)
	return _trimmed(("%." + str(decimals(step)) + "f") % value)


## "W x H x D" in that order, or "" for no size at all.
static func dimensions(dims: Vector3, step: float = 0.0) -> String:
	if dims == Vector3.ZERO:
		return ""
	return "%s x %s x %s" % [number(dims.x, step), number(dims.y, step), number(dims.z, step)]


## "X, Y, Z" for a point.
static func point(value: Vector3, step: float = 0.0) -> String:
	return "%s, %s, %s" % [number(value.x, step), number(value.y, step), number(value.z, step)]


## An area, to the precision of a square of the grid step: 0.0625 on a 0.25 grid.
static func area(value: float, step: float = 0.0) -> String:
	return number(value, step * step if step > 0.0 else 0.0)


## A direction, which is not a length and has no grid: three places.
static func direction(value: Vector3) -> String:
	var places := "%.3f"
	return (
		"%s, %s, %s"
		% [_trimmed(places % value.x), _trimmed(places % value.y), _trimmed(places % value.z)]
	)


static func _trimmed(text: String) -> String:
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	# A small negative rounds to "-0", which reads as a sign that means something.
	return "0" if text == "-0" else text


static func _is_whole(value: float) -> bool:
	return absf(value - roundf(value)) < 0.000001 * maxf(1.0, absf(value))
