using PyCall, Dates, WGLMakie, AbstractPlotting, JSServe, ImageCore, FilePathsBase, CSV, DataFrames, HTTP, Pkg.TOML, Tar, FileIO, ImageMagick, LibSerialPort, Observables, Tables, TableOperations
using FilePathsBase: /
using JSServe.DOM
using JSServe: @js_str

py"""
import picamera
import io

def PC():
    return picamera.PiCamera()

def PIO():
    return io.BytesIO()
"""

const datadir = p"/home/pi/mnt/data"
isdir(datadir) || mkpath(datadir)

const nicolas = Base.Libc.gethostname() == "nicolas"
# "https://docs.google.com/spreadsheets/d/e/2PACX-1vSDVystEejAu9O34P4GNYh8J7DZyz87GadWt-Ak3BrRMcdIO9PjWJbiWuS8MmjQr22JDNYnbtdplimv/pub?gid=0&single=true&output=csv"
const setupsurl = nicolas ? "https://docs.google.com/spreadsheets/d/e/2PACX-1vSfv92ymTJjwdU-ft9dgglOOnxPVWwtk6gFIVSocHM3jSfHkjYk-mtEXl3g96-735Atbk1LBRt-8lAY/pub?gid=0&single=true&output=csv" : "https://docs.google.com/spreadsheets/d/e/2PACX-1vSfv92ymTJjwdU-ft9dgglOOnxPVWwtk6gFIVSocHM3jSfHkjYk-mtEXl3g96-735Atbk1LBRt-8lAY/pub?gid=0&single=true&output=csv"
const button_class = "bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded"
const grid_class = "grid auto-cols-max grid-cols-2 md:grid-cols-3 lg:grid-cols-5 gap-4"
const text_class = "border py-2 px-3 text-grey-darkest"
const bucket = nicolas ? "nicolas-cage-skyroom" : "top-floor-skyroom2"
const baudrate = 9600

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

const framerate = 30
allwind = nicolas ? AllWind([FanArduino(id, port) for (id, port) in enumerate(fan_ports) if isconnected(port)], 1)  : nothing
led_arduino = LEDArduino()
camera = PiCamera(framerate, 67, 67, 4)

const data = Observable((frame = snap(camera), trpms = get_rpms(allwind)))
task = @async while isopen(allwind) && isopen(camera)
    try
        data[] = (; frame = snap(camera), trpms = get_rpms(allwind))
        sleep(0.01)
    catch e
        @warn exception = e
    end
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

function get_setups()
    setup_file = download(setupsurl)
    df = CSV.File(setup_file, header = 1:2, types = Dict(1 => String)) |> TableOperations.filter(x -> !ismissing(Tables.getcolumn(x, :setup_label))) |> TableOperations.transform(setup_label = strip) |> DataFrame
    select(df, :setup_label => identity => :label, r"fan" => ByRow(parse2wind ∘ tuple) => :fans, r"star" => ByRow(parse2stars ∘ tuple) => :stars)
end

_fun(::Nothing, _) = nothing
_fun(allwind, setup) = for a in allwind.arduinos
    a.pwm[] = setup.fans[a.id].pwm
end

function button(setup, setuplog)
    b = JSServe.Button(setup.label, class = button_class)
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

function record(tf, setuplog)
    if tf
        timestamp[] = string(now())
        folder = datadir / timestamp[]
        mkdir(folder)
        camera.cam.recording && camera.cam.stop_recording()
        camera.cam.start_recording(string(folder / "video.h264"))
        record(allwind, folder)
        deleteat!(setuplog, 1:length(setuplog) - 1)
    else
        camera.cam.stop_recording()
        stop_record(allwind)
    end
end

function save(donesave, recording, saving_now, timestamp, beetleid, comment, setuplog, left2upload)
    while recording[]
        @info "waiting for the recording to end"
    end
    saving_now[] = true
    md = Dict()
    md["timestamp"] = timestamp[]
    md["beetleid"] = beetleid[]
    md["comment"] = comment[]
    md["setuplog"] = Dict(string(t) => v for (t,v) in setuplog)
    folder = datadir / timestamp[]
    open(folder / "metadata.toml", "w") do io
        TOML.print(io, md)
    end
    left2backup[] += 1
    saving_now[] = false
end

function backup(left2backup)
    for folder in readpath(datadir)
        tmp = Tar.create(string(folder))
        rm(folder, recursive = true)
        name = basename(folder)
        run(`aws s3 mv $tmp s3://$bucket/$name.tar --quiet`)
        left2backup[] = length(readdir(datadir))
    end
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




function handler(session, request)
    filter!(((k,s),) -> !isopen(s), app.sessions)
    empty!(WGLMakie.SAVE_POINTER_IDENTITY_FOR_TEXTURES)
    data2 = copy_observable(data, session)

    frame = map(data2) do x
        x.frame
    end
    trpms = map(data2) do x
        x.trpms
    end

    rpmplot = plotrpm(trpms)
    frameplot = image(frame, scale_plot = false, show_axis = false)
    disconnect!(AbstractPlotting.camera(frameplot))

    recording = JSServe.Checkbox(false)
    on(x -> record(x, setuplog), recording)

    comment = JSServe.TextField("", class = text_class)
    beetleid = JSServe.TextField("", class = text_class)
    timestamp = Ref("")
    setuplog = []

    saving = JSServe.Button("Save", class = button_class)
    on(saving) do _
        if recording[] 
            recording[] = false
        end
    end
    saving_now = Observable(false)
    on(x -> save(x, recording, saving_now, timestamp, beetleid, comment, setuplog, left2upload), saving)

    on(saving_now) do tf
        if !tf
            comment[] = ""
            beetleid[] = ""
        end
    end

    backingup = JSServe.Button("Backup", class = button_class)
    left2backup = Observable(length(readdir(datadir)))
    on(_ -> backup(left2backup), backingup)


    setups = get_setups()
    buttons = button.(eachrow(setups), Ref(setuplog))

    print_sizes()

    return DOM.div(JSServe.TailwindCSS,
        DOM.div(rpmplot),
        DOM.div(frameplot),
        DOM.div(buttons..., class = grid_class),
        DOM.div("Record ", recording),
        DOM.div("Beetle ID ", beetleid),
        DOM.div("Comment ", comment),
        DOM.div(saving),
        DOM.div(backingup, left2backup, " runs left to backup"), 
        class = "grid grid-cols-1 gap-4"
    )
end


app = JSServe.Application(handler, "0.0.0.0", 8082);

function print_sizes()
    mem = Pair{String, Int}[]
    for m in values(Base.loaded_modules), vs in names(m, all = true)
        if isdefined(m, vs)
            v = getfield(m, vs)
            x = Base.summarysize(v)
            if x > 10^6
                push!(mem, string(m, "; ", vs, ": ") => x) 
            end
        end
    end
    sort!(mem, by = last, rev = true)
    n = length(mem)
    if n > 15
        deleteat!(mem, 16:n)
    end
    println("Memory usage:")
    for (txt, i) in mem
        println(txt, Base.format_bytes(i))
    end
    println("")
end








#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#
#








#=
function recordfans(trpms, folder, ids)
fan_io = open(folder / "fans.csv", "w")
println(fan_io, "time,", join([join(["fan$(id)_speed$j" for j in 1:3], ",") for id in ids], ","))
on(trpms) do (t, rpms)
println(fan_io, t, ",",join(Iterators.flatten(rpms), ","))
end
end




function dom_handler(sr::SkyRoom1, left2upload, session, request)

# restart(sr)

empty!(sr.data.listeners)

frame = map(sr.data) do x
x.frame
end
trpms = map(sr.data) do x
x.trpms
end

rpms = map(trpms) do (_, x)
[ismissing(x) ? 0.0 : x for x in Iterators.flatten(x)]
end

md = Dict()

setup_file = download(setupsurl["skyroom"])
df = CSV.File(setup_file, header = 1:2, types = Dict(1 => String))  |> TableOperations.transform(setup_label = strip) |> DataFrame

setuplog = similar(df[1:1,:])
setuplog[:, :time] .= now()
empty!(setuplog)

setups = select(df, :setup_label => identity => :label, r"fan" => ByRow(parse2wind ∘ tuple) => :fans, r"star" => ByRow(parse2stars ∘ tuple) => :stars)
options = collect(df.setup_label)
option = Node(first(options))
setup = map(option) do o
i = findfirst(==(o), options)
push!(setuplog, merge((; time = now()), NamedTuple(df[i,:])))
setups[i, :]
end

on(setup) do x
for _ in 1:3
update_arena!(sr.wind_arduinos, sr.led_arduino, x)
sleep(0.05)
end
end


# GC.gc(true)

fanrecording = Observable(recordfans(trpms, tmpdir(), [a.id for a in sr.wind_arduinos]))
off(trpms, fanrecording[])

recordingtime = Node(now())
timestamp = map(string, recordingtime)
timestamp[] = ""
recording = JSServe.Checkbox(false)

on(recording) do tf
if tf
delete!(setuplog, 1:nrow(setuplog) - 1)
recordingtime[] = now()
folder = datadir / timestamp[]
mkdir(folder)
sr.camera.cam.start_recording(string(folder / "video.h264"))
fanrecording[] = recordfans(trpms, folder, [a.id for a in sr.wind_arduinos])
else
off(trpms, fanrecording[])
sr.camera.cam.stop_recording()
end
end
comment = JSServe.TextField("")
beetleid = JSServe.TextField("")
save = JSServe.Button("Save")
on(save) do _
if recording[] 
recording[] = false
end

md["setup"] = todict(setup[])
md["recording_time"] = recordingtime[]
md["beetle_id"] = beetleid[]
md["comment"] = comment[]
folder = datadir / timestamp[]
open(folder / "metadata.toml", "w") do io
TOML.print(io, md)
end
CSV.write(folder / "setups_log.csv", setuplog)

timestamp[] = ""
comment[] = ""
beetleid[] = ""
end
upload = JSServe.Button("Backup")
on(_ -> backup(left2upload, "nicolas-cage-skyroom"), upload)
left2upload_label = map(left2upload) do i
if i > 0
string(round(Int, 100i), "% left to upload...")
else
"all backed up"
end
end

# GC.gc(true)

colors = repeat(1:5, inner = [3])
rpmx = vcat(((i - 1)*4 + 1 : 4i - 1 for i in 1:5)...)
rpmplot = Scene(show_axis = false, resolution = (540, round(Int, 3*5 + 3*540/(3*5+4))))
barplot!(rpmplot, rpmx, top_rpm*ones(3*5), color = :white, strokecolor = :black, strokewidth = 1)
barplot!(rpmplot, rpmx, rpms, color = colors, strokecolor = :transparent, strokewidth = 0)
disconnect!(AbstractPlotting.camera(rpmplot))

frameplot = image(frame, scale_plot = false, show_axis = false)
disconnect!(AbstractPlotting.camera(frameplot))

# GC.gc(true)

# print_sizes()

empty!(WGLMakie.SAVE_POINTER_IDENTITY_FOR_TEXTURES)

return DOM.div(
DOM.div(rpmplot),
DOM.div(frameplot),
DOM.div("Setup: ", dropdown(options, option)),
DOM.div("Recording: ", recording, timestamp),
DOM.div("ID: ", beetleid),
DOM.div("Comment: ", comment),
DOM.div(save),
DOM.div(upload, left2upload_label)
)

end

function dom_handler(sr::SkyRoom2, left2upload, session, request)

# restart(sr)
empty!(sr.frame.listeners)

md = Dict()
setup_file = download(setupsurl["skyroom2"])
df = CSV.File(setup_file, header = 1:2, types = Dict(1 => String))  |> TableOperations.transform(setup_label = strip) |> DataFrame
setups = select(df, :setup_label => identity => :label, r"star" => ByRow(parse2stars ∘ tuple) => :stars)
options = collect(df.setup_label)
option = Node(first(options))
setup = map(option) do o
i = findfirst(==(o), options)
setups[i, :]
end

on(setup) do x
for _ in 1:3
sr.led_arduino.pwm[] = parse2arduino(x.stars)
sleep(0.05)
end
end

# GC.gc(true)

recordingtime = Node(now())
timestamp = map(string, recordingtime)
timestamp[] = ""
recording = JSServe.Checkbox(false)
on(recording) do tf
if tf
recordingtime[] = now()
folder = datadir / timestamp[]
mkdir(folder)
sr.camera.cam.start_recording(string(folder / "video.h264"))
else
sr.camera.cam.stop_recording()
end
end
comment = JSServe.TextField("")
beetleid = JSServe.TextField("")
save = JSServe.Button("Save")
on(save) do _
if recording[] 
recording[] = false
end

md["setup"] = todict(setup[])
md["recording_time"] = recordingtime[]
md["beetle_id"] = beetleid[]
md["comment"] = comment[]
folder = datadir / timestamp[]
open(folder / "metadata.toml", "w") do io
TOML.print(io, md)
end

timestamp[] = ""
comment[] = ""
beetleid[] = ""
end
upload = JSServe.Button("Backup")
on(_ -> backup(left2upload, "top-floor-skyroom2"), upload)
left2upload_label = map(left2upload) do i
if i > 0
string(round(Int, 100i), "% left to upload...")
else
"all backed up"
end
end

# GC.gc(true)

frameplot = image(sr.frame, scale_plot = false, show_axis = false)
disconnect!(AbstractPlotting.camera(frameplot))

# GC.gc(true)

# print_sizes()

empty!(WGLMakie.SAVE_POINTER_IDENTITY_FOR_TEXTURES)

return DOM.div(
DOM.div(frameplot),
DOM.div("Setup: ", dropdown(options, option)),
DOM.div("Recording: ", recording, timestamp),
DOM.div("ID: ", beetleid),
DOM.div("Comment: ", comment),
DOM.div(save),
DOM.div(upload, left2upload_label)
)
end

# function print_sizes()
#     sizes = sort(filter(x-> x[2] > 5*(10^6), map(collect(values(Base.loaded_modules))) do m
#                             m=>Base.summarysize(m)
#                         end), rev=true, by=last)
#     foreach(((m, s),)-> println(m, ": ", Base.format_bytes(s)), sizes)
#     println("Free: ", Base.format_bytes(Sys.free_memory()))
# end

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
#     if n > 15
#         deleteat!(mem, 16:n)
#     end
#     println("Memory usage:")
#     for (txt, i) in mem
#         println(txt, Base.format_bytes(i))
#     end
#     println("")
# end



left2upload = Observable(0.0)
if  Base.Libc.gethostname() == "sheldon"
skyroom2 = SkyRoom2()
restart(skyroom2)
app = JSServe.Application((a, b) -> dom_handler(skyroom2, left2upload, a, b), "0.0.0.0", port);
elseif Base.Libc.gethostname() == "nicolas"
skyroom = SkyRoom1()
restart(skyroom)
app = JSServe.Application((a, b) -> dom_handler(skyroom, left2upload, a, b), "0.0.0.0", port);
else
error("where am I")
end=#

