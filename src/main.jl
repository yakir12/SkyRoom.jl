mutable struct SkyRoom2
    led_arduino::LEDArduino
    camera::PiCamera
    frame::Observable
    function SkyRoom2()
        led_arduino = LEDArduino(led_port["skyroom2"])
        camera = PiCamera(30, 67, 67, 4)
        frame = Observable(snap(camera))
        new(led_arduino, camera, frame)
    end
end

connect!(a::SkyRoom2) = @async while isopen(a.camera)
    a.frame[] = snap(a.camera)
    sleep(0.01)
end

function restart(a::SkyRoom2)
    empty!(a.frame.listeners)
    restart(a.led_arduino)
    restart(a.camera)
    connect!(a)
end


mutable struct SkyRoom
    wind_arduinos::Vector{FanArduino}
    led_arduino::LEDArduino
    camera::PiCamera
    data::Observable
    function SkyRoom()
        wind_arduinos = [FanArduino(id, port) for (id, port) in enumerate(fan_ports) if isconnected(port)]
        led_arduino = LEDArduino(led_port["skyroom"])
        camera = PiCamera(30, 67, 67, 4)
        data = Observable((; frame = snap(camera), trpms = get_rpms(wind_arduinos)))
        new(wind_arduinos, led_arduino, camera, data)
    end
end

connect!(a::SkyRoom) = @async while all(isopen, a.wind_arduinos) && isopen(a.camera)
    a.data[] = (; frame = snap(a.camera), trpms = get_rpms(a.wind_arduinos))
    sleep(0.01)
end

function restart(a::SkyRoom)
    empty!(a.data.listeners)
    restart.(a.wind_arduinos)
    restart(a.led_arduino)
    restart(a.camera)
    connect!(a)
end

function main(le)
    left2upload = Observable(0.0)
    if le
        skyroom2 = SkyRoom2()
        app = JSServe.Application((a, b) -> dom_handler(skyroom2, left2upload, a, b), "0.0.0.0", port);
    else
        skyroom = SkyRoom()
        app = JSServe.Application((a, b) -> dom_handler(skyroom, left2upload, a, b), "0.0.0.0", port);
    end
end

function dropdown(options, option)
    dropdown_onchange = js"update_obs($option, this.options[this.selectedIndex].text);"
    DOM.select(DOM.option.(options); class="bandpass-dropdown", onclick=dropdown_onchange)
end


function record(folder, fan_io, wind_arduinos, camera)
    fan_io1 = open(folder / "fans.csv", "w")
    println(fan_io1, "time,", join([join(["fan$(a.id)_speed$j" for j in 1:3], ",") for a in wind_arduinos], ","))
    fan_io[] = fan_io1
    file = string(folder / "video.h264")
    camera.start_recording(file)
end

# label_setup(x) = string("fans=", Int[i.pwm for i in x.fans], "; stars=", [string(i.cardinality, " ", i.elevation, " ", i.intensity, " ", i.radius) for i in x.stars])


function update_arena!(wind_arduinos, led_arduino, setup)
    for a in wind_arduinos
        a.pwm[] = setup.fans[a.id].pwm
    end
    led_arduino.pwm[] = parse2arduino(setup.stars)
end

function backup(left2upload, bucket)
    left2upload[] = 1.0
    n = length(readpath(datadir))
    for (i, folder) in enumerate(readpath(datadir))
        tmp = Tar.create(string(folder))
        rm(folder, recursive = true)
        name = basename(folder)
        run(`aws s3 mv $tmp s3://$bucket/$name.tar --quiet`)
        left2upload[] = (n - i)/n
    end
end


typedict(x::T) where {T} = Dict(fn=>getfield(x, fn) for fn ∈ fieldnames(T))

function todict(setup)
    x = Dict(pairs(setup))
    if haskey(x, :fans)
        x[:fans] = typedict.(x[:fans])
    end
    x[:stars] = typedict.(x[:stars])
    return x
end


function dom_handler(sr::SkyRoom, left2upload, session, request)

    restart(sr)

    frame = map(sr.data) do x
        x.frame
    end
    trpms = map(sr.data) do x
        x.trpms
    end

    rpms = map(trpms) do (_, x)
        [ismissing(x) ? 0.0 : x for x in Iterators.flatten(x)]
    end

    tmpio = open(tempname(), "w")
    close(tmpio)
    fan_io = Node{IO}(tmpio)

    on(trpms) do (t, rpms)
        println(fan_io[], t, ",",join(Iterators.flatten(rpms), ","))
    end

    md = Dict()

    setup_file = HTTP.get(setupsurl["skyroom"]).body
    df = CSV.File(setup_file, header = 1:2) |> DataFrame

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
            record(folder, fan_io, sr.wind_arduinos, sr.camera.cam)
        else
            sr.camera.cam.stop_recording()
            close(fan_io[])
            fan_io[] = tmpio
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

    colors = repeat(1:5, inner = [3])
    rpmx = vcat(((i - 1)*4 + 1 : 4i - 1 for i in 1:5)...)
    rpmplot = Scene(show_axis = false, resolution = (540, round(Int, 3*5 + 3*540/(3*5+4))))
    barplot!(rpmplot, rpmx, top_rpm*ones(3*5), color = :white, strokecolor = :black, strokewidth = 1)
    barplot!(rpmplot, rpmx, rpms, color = colors, strokecolor = :transparent, strokewidth = 0)
    disconnect!(AbstractPlotting.camera(rpmplot))

    frameplot = image(frame, scale_plot = false, show_axis = false)
    disconnect!(AbstractPlotting.camera(frameplot))

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

    restart(sr)

    md = Dict()
    setup_file = HTTP.get(setupsurl["skyroom2"]).body
    df = CSV.File(setup_file, header = 1:2) |> DataFrame
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
    on(_ -> backup(left2upload, "top-room-skyroom2"), upload)
    left2upload_label = map(left2upload) do i
        if i > 0
            string(round(Int, 100i), "% left to upload...")
        else
            "all backed up"
        end
    end

    frameplot = image(sr.frame, scale_plot = false, show_axis = false)
    disconnect!(AbstractPlotting.camera(frameplot))

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



# close(led_arduino); close.(wind_arduinos); camera.close()
