const top_rpm = 12650
const t4 = 15000000
const baudrate = 9600
const shortest_t = t4/1.1top_rpm
const fan_ports = ["/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323510141D0-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95635333930351917172-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95735353032351010260-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_55838323435351213041-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323514121D0-if00"]
const rpmplt_cont = (colors = repeat(1:5, inner = [3]), x = vcat(((i - 1)*4 + 1 : 4i - 1 for i in 1:5)...), y = top_rpm*ones(3*5), resolution = (540, round(Int, 3*5 + 3*540/(3*5+4))))


struct Wind
    id::Int
    pwm::UInt8
end
Wind(id::Int, ::Missing) = Wind(id, 0x00)

parse2wind(windrow) = [Wind(id, v) for (id, v) in enumerate(windrow)]

tosecond(t::T) where {T <: TimePeriod}= t/convert(T, Second(1))
t₀ = now()
sincestart(t) = tosecond(t - t₀)

function toint(msg)
    y = zero(UInt32)
    for c in msg
        y <<= 8
        y += c
    end
    return y
end

getrpm(t) = t < shortest_t ?  missing : t4/t

function set_pwm!(sp, c, pwm)
    lock(c) do
        sp_flush(sp, SP_BUF_INPUT)
        encode(sp, pwm)
    end
end

function update_rpm!(sp, c, pwm, msg, rpm)
    if pwm[] > 19
        lock(c) do 
            sp_flush(sp, SP_BUF_OUTPUT)
            decode!(msg, sp, 12) 
        end
        for (i, x) in enumerate(Iterators.partition(msg, 4))
            rpm[i] = getrpm(toint(x))
        end
    else
        fill!(rpm, 0.0)
    end
end

function isconnected(port)
    try 
        sp = LibSerialPort.open(port, baudrate)
        close(sp)
        true
    catch ex
        false
    end
end

mutable struct FanArduino <: AbstractArduino
    id::Int
    c::ReentrantLock
    port::String
    sp::SerialPort
    msg::Vector{UInt8}
    rpm::Vector{Union{Missing, Float64}}
    pwm::Observable{UInt8}
    function FanArduino(id::Int, port::String)
        c = ReentrantLock()
        sp = LibSerialPort.open(port, baudrate)
        pwm = Observable(0x00)
        msg = Vector{UInt8}(undef, 12)
        rpm = Vector{Float64}(undef, 3)
        new(id, c, port, sp, msg, rpm, pwm)
    end
end

connect!(a::FanArduino) = on(a.pwm) do x
    set_pwm!(a.sp, a.c, x)
end

update_rpm!(a::FanArduino) = update_rpm!(a.sp, a.c, a.pwm, a.msg, a.rpm)

get_rpm(a::FanArduino) = a.rpm

get_rpms(_::Vector{IOStream}) = nothing
function get_rpms(arduinos::Vector{FanArduino})
    @sync for a in arduinos
        @async update_rpm!(a)
    end
    now() => get_rpm.(arduinos)
end

