fetch_setups(setup_file) = CSV.File(setup_file, header = 1:2) |> DataFrame

function parse_setups(df)
    map(eachrow(df)) do r
        fans = parse2wind(r[r"fan"])
        stars = parse2stars(r[r"star"])
        (; fans, stars)
    end
end

label_setup(x) = string("fans=", Int[i.pwm for i in x.fans], "; stars=", join([string(i.cardinality, " ", i.elevation, " ", i.intensity, " ", i.radius) for i in x.stars], ","))

update_arena!(wind_arduinos, led_arduino, ::Nothing) = nothing
function update_arena!(wind_arduinos, led_arduino, setup)
    for a in wind_arduinos
        a.pwm[] = setup.fans[a.id].pwm
        sleep(0.001) # see if that helps
    end
    led_arduino.msg[] = parse2arduino(setup.stars)
end

function record(setup, camera, wind_arduinos, frame, trpms)

    open(camera)

    folder = datadir / string(now())

    mkdir(folder)

    open(folder / "setup.txt", "w") do io
        print(io, label_setup(setup))
    end

    fan_io = open(folder / "fans.csv", "w")
    println(fan_io, "time,", join([join(["fan$(a.id)_speed$j" for j in 1:3], ",") for a in wind_arduinos], ","))

    tmp = folder / "temp.stream"

    open(tmp, "w") do stream_io
        i = 0
        while isopen(camera)
            i += 1

            img = get_frame(camera)
            appendencode!(camera.encoder, stream_io, img, i)

            t, rpms = get_rpms(wind_arduinos)
            println(fan_io, t, ",",join(Iterators.flatten(rpms), ","))

            frame[] = img
            trpms[] = t => rpms
        end
        finishencode!(camera.encoder, stream_io)
    end
    close(fan_io)

    camera.encoder = prepareencoder(camera.buff; framerate, AVCodecContextProperties, codec_name)

end

function play(camera, wind_arduinos, frame, trpms)
    open(camera)
    while isopen(camera)
        trpms[] = get_rpms(wind_arduinos)
        frame[] = get_frame(camera)
        sleep(0.0001)
    end
end

function backup()
    todo = readpath(datadir)
    n = length(todo)
    done = Vector{SystemPath}(undef, n)
    @showprogress 1 "Uploading..." for (i, folder) in enumerate(todo)
        tmp = folder / "temp.stream"
        video = folder / "track.mp4"
        mux(tmp, video, framerate, silent = true)

        tb = Tar.create(string(folder))
        source = AbstractPath(tb)
        name = basename(folder)
        destination = S3Path(bucket, name * ".tar", config = s3config)
        mv(source, destination)
        @assert AWSS3.s3_exists(s3config, "dackebeetle", name * ".tar") "upload failed for $name"
        done[i] = folder
    end
    foreach(done) do folder
        rm(folder, recursive = true)
    end
end



function main(; setup_file = HTTP.get(setupsurl).body, fan_ports = ["/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323510141D0-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95635333930351917172-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95735353032351010260-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_55838323435351213041-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323514121D0-if00"], led_port = "/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0", cam_url = "http://130.235.245.118:8080/stream/video.mjpeg")

    wind_arduinos = [FanArduino(id, port) for (id, port) in enumerate(fan_ports) if isconnected(port)]
    led_arduino = LEDArduino(led_port)
    camera = PiCam(cam_url)

    frame = Observable(camera.buff)

    trpms = Observable(get_rpms(wind_arduinos))
    reading_fans = @async while all(isopen, wind_arduinos)
        trpms[] = get_rpms(wind_arduinos)
        sleep(0.001) # rm later
    end

    history = 50
    rpmlines = [[Observable(CircularBuffer{Point2f0}(history)) for _ in 1:3] for _ in wind_arduinos] # put in zeros
    on(trpms) do (t, rpms)
        for (rpmline, rpm) in zip(rpmlines, rpms), (rpmlin, rp) in zip(rpmline, rpm)
            if !ismissing(rp)
                push!(rpmlin[], Point2f0(sincestart(t), rp))
                rpmlin[] = rpmlin[]
            end
        end
    end

    scene, layout = layoutscene()

    df = Observable(fetch_setups(setup_file))
    setups = map(parse_setups, df)
    options = map(setups) do x
        zip(label_setup.(x), x)
    end
    ui = LMenu(scene, options = options, width =  Auto())
    update = LButton(scene, label = "Update")
    on(update.clicks) do _
        df[] = fetch_setups(setup_file)
    end
    on(ui.selection) do o
        update_arena!(wind_arduinos, led_arduino, o)
    end

    toggle = LToggle(scene, active = false)
    lable = LText(scene, lift(x -> x ? "recording" : "playing", toggle.active))


    on(toggle.active) do tf
        if tf
            close(camera)
            @async record(ui.selection[], camera, wind_arduinos, frame, trpms)
        else 
            close(camera)
            sleep(1)
            @async play(camera, wind_arduinos, frame, trpms)
        end
    end


    upload = LButton(scene, label = "Backup")
    on(upload.clicks) do _
        close(camera)
        backup()
        @async play(camera, wind_arduinos, frame, trpms)
    end

    buttongrid = GridLayout(tellwidth = true, tellheight = true)
    buttongrid[1,1] = update
    buttongrid[1,2] = ui
    buttongrid[1,3] = grid!(hcat(toggle, lable), tellheight = false)
    buttongrid[1,4] = upload

    img_ax = LAxis(scene, aspect = DataAspect())
    image!(img_ax, lift(rotr90, frame))
    hidedecorations!(img_ax)
    tightlimits!(img_ax)
    for interaction in keys(AbstractPlotting.MakieLayout.interactions(img_ax))
        deregister_interaction!(img_ax, interaction)
    end

    colors = range(Gray(0.0), Gray(0.75), length = 3)

    rpmgrid = GridLayout()
    axs = rpmgrid[:h] = [LAxis(scene, ylabel = "RPM", title = "Fan #$(a.id)", xticklabelsvisible = false) for a in wind_arduinos]
    for (i, o) in enumerate(rpmlines), (line, color) in zip(o, colors)
        lines!(axs[i], line; color)
    end
    on(rpmlines[1][1]) do o
        xmin, xmax = extrema(first, o)
        xmax += 1
        axs[1].targetlimits[] = FRect2D(xmin, 0, xmax - xmin, top_rpm)
    end
    linkaxes!(axs...)
    hideydecorations!.(axs[2:end], grid = false)
    for ax in axs, interaction in keys(AbstractPlotting.MakieLayout.interactions(ax))
        deregister_interaction!(ax, interaction)
    end

    layout[1, 1] = buttongrid
    layout[2, 1] = img_ax
    layout[3, 1] = rpmgrid


    @async play(camera, wind_arduinos, frame, trpms)

    on(scene.events.window_open) do tf
        if !tf
            close.(wind_arduinos)
            close(led_arduino)
            close(camera)
        end
    end

    scene
end
