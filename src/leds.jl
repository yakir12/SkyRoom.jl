const strips = 2
const ledsperstrip = 150
const brightness = 1
const deadleds = 9
const cardinals = ["NE", "SW", "SE", "NW"]
const liveleds = ledsperstrip - deadleds
const ledport = nicolas ? "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_757353036313519070B1-if00" : "/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0"
# const ledport = "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95735353032351317061-if00"

struct Star
    cardinality::String
    elevation::Int
    intensity::Int
    radius::Int
end
Star(a::String, b::String, c::String, d::String) = Star(a, parse(Int, b), parse(Int, c), parse(Int, d))

struct LED
    ind1::UInt8
    ind2::UInt8
    intensity::UInt8
    buff::Vector{UInt8}
    LED(ind1, ind2, intensity) = new(ind1, ind2, intensity, [ind1, ind2, 0x00, intensity, 0x00])
end


function index2led(c::Int, e)
    a = isodd(c) ? e : liveleds - e + 1
    b = c < 3 ? 0 : ledsperstrip
    pos = a + b - 1
    pos == (liveleds - 1)/2 ? ledsperstrip + pos : pos
end

function LED(s::Star)
    c = findfirst(==(s.cardinality), cardinals)
    intensity = s.intensity
    map(-s.radius:s.radius) do i
        pos = index2led(c, s.elevation)
        ind = pos + i
        ind2, ind1 = reinterpret(UInt8, [UInt16(ind)])
        LED(ind1, ind2, intensity)
    end
end

parse2arduino(leds::Vector{LED}) = vcat((led.buff for led in leds)...)
parse2arduino(stars::Vector{Star}) = isempty(stars) ? zeros(UInt8, 5) : vcat((parse2arduino(LED(star)) for star in stars)...)

mutable struct LEDArduino <: AbstractArduino
    port::String
    sp::SerialPort
    pwm::Observable{Vector{UInt8}}
    function LEDArduino()
        sp = LibSerialPort.open(ledport, baudrate)
        pwm = Observable(UInt8[0, 0])
        on(pwm) do x
            encode(sp, x)
        end
        new(ledport, sp, pwm)
    end
end
