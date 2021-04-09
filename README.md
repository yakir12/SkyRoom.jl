# SkyRoom

## Instructions
1. Go to the setup link, edit your setups.
2. Go to the GUI link, control the arena.
3. Go to the results link, download your results.

## Top-floor sky-room (Sheldon)
- [Link to setups file](https://docs.google.com/spreadsheets/d/1-NWBK6dzDvXiULAtpFn5WIC888An21m0483jLv8CiS0/edit?usp=sharing)
- [Link to GUI](http://130.235.245.94:8082/)
- [Link to results](https://top-floor-skyroom2.s3.eu-north-1.amazonaws.com/list.html)

## Bottom-floor sky-room (Nicolas Cage)
- [Link to setups file](https://docs.google.com/spreadsheets/d/1PJPT2xJ6Ggx-byg4FRdIbIkDWuJxN28zpATHAGHpgLY/edit?usp=sharing)
- [Link to GUI](http://130.235.245.92:8082/)
- [Link to results](https://nicolas-cage-skyroom.s3.eu-north-1.amazonaws.com/list.html)

## Instructions for the toml setup file
### Star
- `intensity` (0-255) for specifying the green light, OR `rgb` (e.g. `[0, 0, 255]` for max blue light) for specifying a specific color
- `elevation` (1-71)
- `cardinal` (`"NE"`, `"NW"`, `"SE"`, or `"SW"`)
- (`radius` (0-Inf; default = 0))

### Milky way
- `cardinals` (e.g. `["SE", "NW"]`) the cardinal arc that the milky way will display on. The order of the cardinal directions dictates which end is brighter
- (`intensity` (0 - Inf; default=1) a factor with which the original intensity of the milky way is multiplied by (so `intensity` < 1 will decrease the intensity of the milky way and vice versa).)
- (`hue` (0-360; default=0) the hue of the resulting color of the milky way
- (`saturation` (0-1; default=0 i.e. white light) the saturation of the resulting color of the milky way
