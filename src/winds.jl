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

struct FanArduino <: AbstractArduino
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
        on(pwm) do x
            set_pwm!(sp, c, x)
        end
        msg = Vector{UInt8}(undef, 12)
        rpm = Vector{Float64}(undef, 3)
        new(id, c, port, sp, msg, rpm, pwm)
    end
end

update_rpm!(a::FanArduino) = update_rpm!(a.sp, a.c, a.pwm, a.msg, a.rpm)

get_rpm(a::FanArduino) = a.rpm

function get_rpms(arduinos::Vector{FanArduino})
    @sync for a in arduinos
        @async update_rpm!(a)
    end
    now() => get_rpm.(arduinos)
end

