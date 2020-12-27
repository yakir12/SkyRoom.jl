struct Wind
    id::Int
    pwm::UInt8
end
Wind(id::Int, ::Missing) = Wind(id, 0x00)
Wind(id::Int, pwm::String) = Wind(id, parse(Int, pwm))

tosecond(t::T) where {T <: TimePeriod}= t/convert(T, Second(1))
sincestart(t) = tosecond(t - t₀[])

function toint(msg)
    y = zero(UInt32)
    for c in msg
        y <<= 8
        y += c
    end
    return y
end

function getrpm(t)
    t4 = 15000000
    shortest_t = t4/1.1top_rpm
    t < shortest_t ?  missing : t4/t
end

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
        sp = LibSerialPort.open(port, baudrate[])
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
        sp = LibSerialPort.open(port, baudrate[])
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

mutable struct AllWind
    arduinos::Vector{FanArduino}
    io::IOStream
    framerate::Int
    function AllWind(arduinos::Vector{FanArduino}, framerate::Int)
        io = open(tempname(), "w")
        close(io)
        new(arduinos, io, framerate)
    end
end

function get_rpms(allwind::AllWind)
    @sync for a in allwind.arduinos
        @async update_rpm!(a)
    end
    now() => get_rpm.(allwind.arduinos)
end

function record(allwind::AllWind, folder)
    !isdir(folder) && mkpath(folder)
    isopen(allwind.io) && close(allwind.io)
    allwind.io = open(folder / "fans.csv", "w")
    println(allwind.io, "time,", join([join(["fan$(a.id)_speed$j" for j in 1:3], ",") for a in allwind.arduinos], ","))
    @async while isopen(allwind.io)
        try 
            t, rpms = get_rpms(allwind)
            println(allwind.io, t, ",",join(Iterators.flatten(rpms), ","))
        catch e
            @warn exception = e
        end
        sleep(1/allwind.framerate)
    end
end

Base.isopen(allwind::AllWind) = all(isopen, allwind.arduinos)
Base.close(allwind::AllWind) = close.(allwind.arduinos)
