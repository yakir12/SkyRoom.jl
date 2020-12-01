abstract type AbstractArduino end

Base.isopen(a::AbstractArduino) = isopen(a.sp)
Base.close(a::AbstractArduino) = isopen(a) && close(a.sp)
function Base.open(a::AbstractArduino) 
    if !isopen(a) 
        a.sp = LibSerialPort.open(a.port, baudrate)
    end
end
restart(a::AbstractArduino) = (close(a); open(a))


