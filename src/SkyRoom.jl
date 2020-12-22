module SkyRoom

export main

using Dates, WGLMakie, AbstractPlotting, JSServe, ImageCore, FilePathsBase, CSV, HTTP, Pkg.TOML, Tar, FileIO, ImageMagick, Observables, PyCall, LibSerialPort, Missings
using FilePathsBase: /
using JSServe.DOM
using JSServe: @js_str

# function print_sizes()
#     mem = Pair{String, Int}[]
#     for m in values(Base.loaded_modules), vs in names(m, all = true)
#         if isdefined(m, vs)
#             v = getfield(m, vs)
#             x = Base.summarysize(v)
#             if x > 10^6
#                 push!(mem, string(m, "; ", vs, ": ") => x) 
#             end
#         end
#     end
#     sort!(mem, by = last, rev = true)
#     n = length(mem)
#     if n > 30
#         deleteat!(mem, 31:n)
#     end
#     println("Memory usage:")
#     for (txt, i) in mem
#         println(txt, Base.format_bytes(i))
#     end
#     println("")
# end

function __init__()
    py"""
    import picamera
    import io

    def PC():
        return picamera.PiCamera()

    def PIO():
        return io.BytesIO()
    """

end

const datadir = p"/home/pi/mnt/data"
isdir(datadir) || mkpath(datadir)

const nicolas = Base.Libc.gethostname() == "nicolas"
const setupsurl = nicolas ? "https://docs.google.com/spreadsheets/d/e/2PACX-1vQNLWhLfp_iuW68j7SM6Px8ysTmbrfmrP_7ipXK9BkfzBgfqn3Mj7ra177mZyHlY5NLA3SDtfYNTROv/pub?gid=0&single=true&output=csv" : "https://docs.google.com/spreadsheets/d/e/2PACX-1vSfv92ymTJjwdU-ft9dgglOOnxPVWwtk6gFIVSocHM3jSfHkjYk-mtEXl3g96-735Atbk1LBRt-8lAY/pub?gid=0&single=true&output=csv"
const button_class = "bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
const grid_class = "grid auto-cols-max grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4"
const text_class = "border py-2 px-3 text-grey-darkest"
const bucket = nicolas ? "nicolas-cage-skyroom" : "top-floor-skyroom2"
const baudrate = 9600
const framerate = 30

include("cobs.jl")
include("abstractarduinos.jl")
include("leds.jl")
if nicolas
    include("winds.jl")
end

get_rpms(::Nothing) = nothing
record(::Nothing, _) = nothing
Base.isopen(::Nothing) = true
Base.close(::Nothing) = nothing

include("camera.jl")


function initialize()
    allwind = nicolas ? AllWind([FanArduino(id, port) for (id, port) in enumerate(fan_ports) if isconnected(port)], 1)  : nothing
    led_arduino = LEDArduino()
    camera = PiCamera(framerate, 67, 67, 4)

    data = Observable((frame = snap(camera), trpms = get_rpms(allwind)))
    task = @async while isopen(allwind) && isopen(camera)
        try
            data[] = (; frame = snap(camera), trpms = get_rpms(allwind))
            sleep(0.01)
        catch e
            @show now()
            print_sizes()
            throw(e)
            break
        end
    end
    return allwind, led_arduino, camera, data, task
end

function plotrpm(trpms)
    if isnothing(trpms[])
        return nothing
    end
    rpms = map(trpms) do (_, x)
        collect(Missings.replace(Iterators.flatten(x), NaN))
    end
    rpmplot = Scene(show_axis = false, resolution = rpmplt_cont.resolution)
    barplot!(rpmplot, rpmplt_cont.x, rpmplt_cont.y, color = :white, strokecolor = :black, strokewidth = 1)
    barplot!(rpmplot, rpmplt_cont.x, rpms, color = rpmplt_cont.colors, strokecolor = :transparent, strokewidth = 0)
    disconnect!(AbstractPlotting.camera(rpmplot))
    return rpmplot
end

parse2wind(windrow) = [Wind(id, v) for (id, v) in enumerate(windrow)]
parse2stars(starsrow) = [Star(v...) for v in Iterators.partition(starsrow, 4) if !any(ismissing, v)]

function parse2one(setup_file)
    rs = NamedTuple{(:label, :stars),Tuple{String,Array{Star,1}}}[]
    for nt in CSV.Rows(setup_file, header = 1:2)
        if !ismissing(nt.setup_label)
            t = Tuple(nt)
            stars = parse2stars(t[2:end])
            push!(rs, (label = t[1], stars = stars))
        end
    end
    rs
end

function parse2both(setup_file)
    rs = NamedTuple{(:label, :fans, :stars),Tuple{String,Array{Wind,1},Array{Star,1}}}[]
    for nt in CSV.Rows(setup_file, header = 1:2)
        if !ismissing(nt.setup_label)
            t = Tuple(nt)
            fans = parse2wind(t[2:6])
            stars = parse2stars(t[7:end])
            push!(rs, (label = t[1], fans = fans, stars = stars))
        end
    end
    rs
end

function get_setups()
    setup_file = download(setupsurl)
    nicolas ? parse2both(setup_file) : parse2one(setup_file)
end

_fun(::Nothing, _) = nothing
_fun(allwind, setup) = for a in allwind.arduinos
    a.pwm[] = setup.fans[a.id].pwm
end

function button(allwind, led_arduino, setup, setuplog)
    b = JSServe.Button(string(setup.label), class = button_class)
    on(b) do _
        _fun(allwind, setup)
        led_arduino.pwm[] = parse2arduino(setup.stars)
        push!(setuplog, now() => todict(setup))
    end
    return b
end

typedict(x::T) where {T} = Dict(fn=>getfield(x, fn) for fn ∈ fieldnames(T))

function todict(setup)
    x = Dict{Symbol, Any}(pairs(setup))
    if haskey(x, :fans)
        x[:fans] = typedict.(x[:fans])
    end
    x[:stars] = typedict.(x[:stars])
    return x
end

stop_record(::Nothing) = nothing
stop_record(allwind) = close(allwind.io)

function record(tf, allwind, camera, timestamp, setuplog)
    if tf
        timestamp[] = string(now())
        folder = datadir / timestamp[]
        !isdir(folder) && mkdir(folder)
        camera.cam.recording && camera.cam.stop_recording()
        camera.cam.start_recording(string(folder / "video.h264"))
        record(allwind, folder)
        deleteat!(setuplog, 1:length(setuplog) - 1)
    else
        camera.cam.stop_recording()
        stop_record(allwind)
    end
end

function save(timestamp, beetleid, comment, setuplog, left2backup, msg)
    folder = datadir / timestamp[]
    if !isdir(folder)
        msg[] = "You haven't recorded a video yet, there is nothing to save"
        return nothing
    end
    msg[] = "Saving"
    md = Dict()
    md["timestamp"] = timestamp[]
    md["beetleid"] = beetleid[]
    md["comment"] = comment[]
    md["setuplog"] = Dict(string(t) => v for (t,v) in setuplog)
    open(folder / "metadata.toml", "w") do io
        TOML.print(io, md)
    end
    left2backup[] += 1
    comment[] = ""
    beetleid[] = ""
    timestamp[] = "garbage"
    msg[] = "Saved"
    return nothing
end

function backup(left2backup, msg)
    msg[] = "Started backing up..."
    for folder in readpath(datadir)
        tmp = Tar.create(string(folder))
        rm(folder, recursive = true)
        name = basename(folder)
        run(`aws s3 mv $tmp s3://$bucket/$name.tar --quiet`)
        left2backup[] = length(readdir(datadir))
    end
    msg[] = "Finished backing up!"
end

function copy_observable(o, session)
    o_copy = Observable(o[])
    listener = on(o) do x
        o_copy[] = x
    end
    on_close(session) do
        off(o, listener)
    end
    return o_copy
end


function on_close(f, session)
    @async begin
        # wait for session to be open
        while !isready(session.js_fully_loaded)
            sleep(0.5)
        end
        # wait for session to close
        while isopen(session)
            sleep(0.5)
        end
        # run on_close callback
        @info("closing session!")
        f()
    end
end




function handler(allwind, led_arduino, camera, data, session, request)
    # filter!(((k,s),) -> !isopen(s), app.sessions)
    empty!(WGLMakie.SAVE_POINTER_IDENTITY_FOR_TEXTURES)
    data2 = copy_observable(data, session)

    msg = Observable("")
    on(msg) do x
        if !isempty(x)
            @async begin
                sleep(3)
                msg[] = ""
            end
        end
    end

    frame = map(data2) do x
        x.frame
    end
    trpms = map(data2) do x
        x.trpms
    end

    rpmplot = plotrpm(trpms)
    frameplot = image(frame, scale_plot = false, show_axis = false)
    disconnect!(AbstractPlotting.camera(frameplot))

    setuplog = []
    timestamp = Ref("")
    recording = JSServe.Checkbox(false)
    on(x -> record(x, allwind, camera, timestamp, setuplog), recording)

    comment = JSServe.TextField("", class = text_class)
    beetleid = JSServe.TextField("", class = text_class)

    saving = JSServe.Button("Save", class = button_class)
    on(saving) do _
        if recording[] 
            recording[] = false
            sleep(0.1)
        end
        save(timestamp, beetleid, comment, setuplog, left2backup, msg)
    end

    backingup = JSServe.Button("Backup", class = button_class)
    left2backup = Observable(length(readdir(datadir)))
    on(_ -> backup(left2backup, msg), backingup)

    setups = get_setups()
    buttons = [button(allwind, led_arduino, setup, setuplog) for setup in setups]

    # print_sizes()

    return DOM.div(JSServe.TailwindCSS,
        DOM.div(rpmplot),
        DOM.div(frameplot),
        DOM.div(buttons..., class = grid_class),
        DOM.div("Record ", recording),
        DOM.div("Beetle ID ", beetleid),
        DOM.div("Comment ", comment),
        DOM.div(saving),
        DOM.div(backingup, left2backup, " runs left to backup"), 
        DOM.div(msg),
        class = "grid grid-cols-1 gap-4"
    )
end

function main()
    allwind, led_arduino, camera, data, task = initialize()
    JSServe.Application((session, request) -> handler(allwind, led_arduino, camera, data, session, request), "0.0.0.0", 8082)
end



end # module

# PyCall, Dates, WGLMakie, AbstractPlotting, JSServe, ImageCore, FilePathsBase, CSV, DataFrames, HTTP, Pkg.TOML, Tar, FileIO, ImageMagick, LibSerialPort, Observables
