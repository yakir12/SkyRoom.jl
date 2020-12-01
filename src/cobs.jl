function encode(msg::Vector{UInt8})
    tuptuo = [0x00]
    lastzero = 0x01
    for x in reverse(msg)
        if iszero(x)
            push!(tuptuo, lastzero)
            lastzero = 0x00
        else
            push!(tuptuo, x)
        end
        lastzero += 0x01
    end
    push!(tuptuo, lastzero)
    return reverse(tuptuo)
end
encode(x::UInt8) = encode([x])
encode(output, msg) = write(output, encode(msg)...)


next!(x) = read(x, UInt8)

function decode!(msg, input, n)
    code = next!(input)
    iszero(code) && return decode!(msg, input, n)
    i = 1
    while true
        code - 1 > n - i + 1 && return decode!(msg, input, n)
        for _ in 1:code - 1
            tmp = next!(input)
            iszero(tmp) && return decode!(msg, input, n)
            msg[i] = tmp
            i += 1
        end
        code = next!(input)
        if iszero(code) 
            if i == n + 1
                return msg
            else
                return decode!(msg, input, n)
            end
        else
            if i > n
                return decode!(msg, input, n)
            else
                msg[i] = 0x00
                i += 1
            end
        end
    end
end

