# Cruise Vector Spaces

Cruise Vector space is a module that allows you to easily manipulate coordinates and colors.
It offers you 2 main kind of vector space:

* `CUnboundedSpace`: Those are space that can extend without limits, mainly to represent coordinates
* `CBoundedSpace`: Those are space with a well defined domain, mainly to represent colors

Using pivot systems (such as `CCartesianCoord` for `CUnboundedSpace` and `CRGBA` for `CBoundedSpace`), Cruise offers an easy to use, extend and understand library.

## Quick start

```nim
import cruise/src/vspace/vspace

let c1 = crgba(0.5, 0.8) # color with just r and g, b and a are equals to 1.0f
let c2 = crgbai(128, 128, 128) # color using uint8 per channel
let c3 = CRed # Predefined color constant, matches CSS constants

echo c2.toHexString
echo c2.toHex
echo convertTo[CHSVColor](c2)
```

## Features

- Easy to extend interface for library that needs to match any user defined types through simple conventions
- Palette of predefined colors
