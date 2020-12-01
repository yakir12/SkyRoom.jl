function recordarena(picsfolder, cardinals, elevations, background)
    p = Progress(length(cardinals)*length(elevations), 1, "Capturing...") 
    for c in eachindex(cardinals), e in eachindex(elevations)
        i = index2led(c, elevations[e])
        filename = joinpath(picsfolder, string(cardinals[c], elevations[e], background, ".png"))
        takeapicture(filename, led = i, options = `--shutter 10000000`)
        next!(p)
    end
    dots = getdots()
    lightsoff(dots)
end
function record_arena_calibration()
    picsfolder = joinpath(tempdir(), constants["calibration"]["arena"]["picsfolder"])
    if !isdir(picsfolder)
        mkdir(picsfolder)
    else
        map(rm, readdir(picsfolder, join = true))
    end

    cardinals = ["NE", "SW", "SE", "NW"]
    elevations = 1:((constants["ledstrip"]["liveleds"] - 1)÷2 + 1)
    i = round.(Int, range(23, 48, length = 3))
    elevations = elevations[i]
    # cardinals = ["NE", "SW"]
    # elevations = [36]
    recordarena(picsfolder, cardinals, elevations, "bkg")

    n = 4
    for i in 1:n
        println("background done, press when ready with sticks, take $i of $n")
        readline()
        recordarena(picsfolder, cardinals, elevations, string(i))
    end
end

