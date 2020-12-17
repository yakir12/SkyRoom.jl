abstract type AbstractArduino end

Base.isopen(a::AbstractArduino) = isopen(a.sp)
Base.close(a::AbstractArduino) = isopen(a) && close(a.sp)
function Base.open(a::AbstractArduino) 
    close(a)
    a.sp = LibSerialPort.open(a.port, baudrate)
    empty!(a.pwm.listeners)
    connect!(a)
end
restart(a::AbstractArduino) = (close(a); open(a))
