struct Star
    cardinality::String
    elevation::Int
    intensity::Int
    radius::Int
end

struct LED
    index::UInt8
    intensity::UInt8
    buff::Vector{UInt8}
    LED(index, intensity) = new(index, intensity, [index, 0x00, intensity, 0x00])
end

function index2led(c::Int, e)
    a = isodd(c) ? e : liveleds - e + 1
    b = c < 3 ? 0 : ledsperstrip
    pos = a + b - 1
    i = pos == (liveleds - 1)/2 ? ledsperstrip + pos : pos
end

function LED(s::Star)
    c = findfirst(==(s.cardinality), cardinals)
    intensity = s.intensity
    map(-s.radius:s.radius) do i
        index = index2led(c, s.elevation + i)
        LED(index, intensity)
    end
end

parse2arduino(leds::Vector{LED}) = vcat((led.buff for led in leds)...)
parse2arduino(stars::Vector{Star}) = isempty(stars) ? zeros(UInt8, 4) : vcat((parse2arduino(LED(star)) for star in stars)...)

function parse2stars(starrow)
    stars = Star[]
    for x in Iterators.partition(starrow, 4)
        if !any(ismissing, x)
            push!(stars,  Star(x...))
        end
    end
    return stars
end

struct LEDArduino <: AbstractArduino
    port::String
    sp::SerialPort
    msg::Observable{Vector{UInt8}}
    function LEDArduino(port::String)
        sp = LibSerialPort.open(port, baudrate)
        msg = Observable(UInt8[0, 0])
        on(msg) do x
            encode(sp, x)
        end
        new(port, sp, msg)
    end
end
