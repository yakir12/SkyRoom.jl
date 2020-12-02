fetch_setups() = CSV.File(HTTP.get(setupsurl).body, header = 1:2) |> DataFrame

function parse_setups(df)
    map(eachrow(df)) do r
        fans = parse2wind(r[r"fan"])
        stars = parse2stars(r[r"star"])
        (; fans, stars)
    end
end

label_setup(x) = string("fans=", Int[i.pwm for i in x.fans], "; stars=", (i for i in x.stars)...)

function update_arena!(wind_arduinos, led_arduino, setup)
    for a in wind_arduinos
        a.pwm[] = setup.fans[a.id].pwm
        sleep(0.01) # see if that helps
    end
    led_arduino.msg[] = parse2arduino(setup.stars)
end

function record(camera, name, frame, playing)
    tmp = tempname()
    open(tmp, "w") do io
        i = 0
        while !playing[]
            i += 1
            img = get_frame(camera)
            appendencode!(camera.encoder, io, img, i)
            frame[] = img
        end
        finishencode!(camera.encoder, io)
    end
    mux(tmp, "$name.mp4", camera.cam.framerate)
    mv(p"$name.mp4", joinpath(s3path, "$name.mp4"))
end

function play(camera, frame, playing)
    while playing[]
        frame[] = get_frame(camera)
        sleep(0.001)
    end
end



function main(; setup_file = HTTP.get(setupsurl).body, fan_ports = ["/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323510141D0-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95635333930351917172-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_95735353032351010260-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_55838323435351213041-if00", "/dev/serial/by-id/usb-Arduino__www.arduino.cc__0043_957353530323514121D0-if00"], led_port = "/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0", cam_url = "http://130.235.245.118:8080/stream/video.mjpeg")

    # df = CSV.File(setup_file, header = 1:2) |> DataFrame
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

    filename = Observable("")
    fanio = Observable{IO}(devnull)
    on(trpms) do (t, rpms)
        println(fanio[], t, ",",join(Iterators.flatten(rpms), ","))
    end

    df = Observable(fetch_setups())
    setups = map(parse_setups, df)
    options = map(setups) do x
        zip(label_setup.(x), x)
    end
    ui = LMenu(scene, options = options, width =  Auto())
    update = LButton(scene, label = "Update")
    on(update.clicks) do _
        df[] = fetch_setups()
    end
    on(ui.selection) do o
        update_arena!(wind_arduinos, led_arduino, o)
    end

    toggle = LToggle(scene, active = false)
    lable = LText(scene, lift(x -> x ? "recording" : "playing", toggle.active))

    playing = Observable(true)
    on(toggle.active) do tf
        if tf
            name = joinpath(tempdir(), string(now(), " ", label_setup(ui.selection[])))
            filename[] = name
            io = open(p"$name.csv", "w")
            println(io, "time,", join([join(["fan$(a.id)_speed$j" for j in 1:3], ",") for a in wind_arduinos], ","))
            fanio[] = io
            playing[] = false

            @async record(camera, name, frame, playing)
        else 
            close(fanio[])
            fanio[] = devnull
            name = filename[]
            mv(p"$name.csv", joinpath(s3path, "$name.csv"))

            playing[] = true
            @async play(camera, frame, playing)
        end
    end

    buttongrid = GridLayout(tellwidth = true, tellheight = true)
    buttongrid[1,1] = update
    buttongrid[1,2] = ui
    buttongrid[1,3] = grid!(hcat(toggle, lable), tellheight = false)

    img_ax = LAxis(scene, aspect = DataAspect(), xzoomlock = true, yzoomlock = true)
    image!(img_ax, lift(rotr90, frame))
    hidedecorations!(img_ax)
    tightlimits!(img_ax)

    colors = range(Gray(0.0), Gray(0.75), length = 3)

    rpmgrid = GridLayout()
    axs = rpmgrid[:h] = [LAxis(scene, ylabel = "RPM", title = "Fan #$(a.id)", xticklabelsvisible = false, xzoomlock = true, yzoomlock = true) for a in wind_arduinos]
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

    layout[1, 1] = buttongrid
    layout[2, 1] = img_ax
    layout[3, 1] = rpmgrid


    playing[] = true
    @async play(camera, frame, playing)

    on(scene.events.window_open) do tf
        if !tf
            close.(wind_arduinos)
            close(led_arduino)
            close(camera)
        end
    end

    scene
end
